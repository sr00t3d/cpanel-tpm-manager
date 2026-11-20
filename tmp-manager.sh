#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                                                                           ║
# ║   cPanel TMP Manager (tmp-manager.sh) v2.0.0                              ║
# ║                                                                           ║
# ╠═══════════════════════════════════════════════════════════════════════════╣
# ║   Autor:   Percio Castelo                                                 ║
# ║   Contato: percio@evolya.com.br | contato@perciocastelo.com.br            ║
# ║   Web:     https://perciocastelo.com.br                                   ║
# ║                                                                           ║
# ║   Função:  Monitors, audits hardening (noexec/nosuid/nodev/sticky bit),   ║
# ║            safely cleans expired files in /tmp and /var/tmp preserving    ║
# ║            active sockets, and resizes tmpfs or cPanel securetmp safely.  ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

set -uo pipefail
export LC_ALL=C

readonly VERSION="2.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="${TMP_MANAGER_LOG:-/var/log/tmp-manager.log}"

# =============================================================================
# Defaults
# =============================================================================
ACTION="status"          # status | clean | resize
TMP_DIR="/tmp"
VAR_TMP="/var/tmp"
TMP_DSK="/usr/tmpDSK"
THRESHOLD=80
AGE_HOURS=12
RESIZE_SIZE=""
FORCE=false
DRY_RUN=false
AUTO_YES=false
OUTPUT_FORMAT="table"    # table | json
NO_COLOR=false
QUIET=false

# =============================================================================
# Colors
# =============================================================================
C_RESET=""
C_BOLD=""
C_RED=""
C_GREEN=""
C_YELLOW=""
C_CYAN=""
C_DIM=""

init_colors() {
    if [[ "$NO_COLOR" == false && "$OUTPUT_FORMAT" == "table" && -t 1 ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[0;31m'
        C_GREEN=$'\033[0;32m'
        C_YELLOW=$'\033[0;33m'
        C_CYAN=$'\033[0;36m'
    fi
}

log_info() { [[ "$QUIET" == false && "$OUTPUT_FORMAT" == "table" ]] && echo -e "${C_CYAN}[→]${C_RESET} $*" >&2; }
log_ok()   { [[ "$QUIET" == false && "$OUTPUT_FORMAT" == "table" ]] && echo -e "${C_GREEN}[+]${C_RESET} $*" >&2; }
log_warn() { [[ "$QUIET" == false ]] && echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; }
log_err()  { echo -e "${C_RED}[✗] Error:${C_RESET} $*" >&2; }

# =============================================================================
# Help
# =============================================================================
show_help() {
    cat <<EOF
cPanel TMP Manager (tmp-manager.sh) v${VERSION}
Monitor, audit hardening, safely clean, and resize /tmp and /var/tmp on Linux/cPanel servers.

Usage:
  ${SCRIPT_NAME} [COMMAND] [OPTIONS]

Commands:
  -s, --status              Audit /tmp & /var/tmp disk/inode usage, mount flags, and top files (default)
  -c, --clean               Safely remove expired files in /tmp & /var/tmp (protects active sockets)
  -r, --resize [SIZE]       Resize tmpfs (e.g. 2048M) or rebuild cPanel /usr/tmpDSK via securetmp

Options:
  -t, --threshold <pct>     Alert/trigger usage threshold percentage (default: 80)
  -a, --age-hours <hours>   Minimum file age in hours for --clean (default: 12)
  -f, --force               Run --clean even when usage is below --threshold
  -n, --dry-run             Simulate cleanup or resize without modifying files/mounts
  -y, --yes                 Skip interactive confirmation prompts (for cron/automation)
  -o, --output <table|json> Output format (default: table)
  -q, --quiet               Suppress progress messages
      --no-color            Disable ANSI colors
  -V, --version             Show version and exit
  -h, --help                Show this help message and exit

Exit Codes:
  0  Healthy / operation completed cleanly
  1  Execution or argument error
  2  /tmp disk or inode usage >= --threshold

Examples:
  ${SCRIPT_NAME} --status
  ${SCRIPT_NAME} --clean --dry-run --age-hours 24 --force
  sudo ${SCRIPT_NAME} --clean --age-hours 12 --threshold 80 -y
  sudo ${SCRIPT_NAME} --resize 2048M -y
  ${SCRIPT_NAME} --status -o json
EOF
}

# =============================================================================
# Argument Parser
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--status)     ACTION="status"; shift ;;
            -c|--clean)      ACTION="clean"; shift ;;
            -r|--resize)
                ACTION="resize"
                if [[ $# -ge 2 && "$2" != -* ]]; then
                    RESIZE_SIZE="$2"; shift 2
                else
                    shift
                fi ;;
            -t|--threshold)  [[ $# -lt 2 ]] && { log_err "$1 requires a number"; exit 1; }; THRESHOLD="$2"; shift 2 ;;
            -a|--age-hours)  [[ $# -lt 2 ]] && { log_err "$1 requires a number"; exit 1; }; AGE_HOURS="$2"; shift 2 ;;
            -f|--force)      FORCE=true; shift ;;
            -n|--dry-run)    DRY_RUN=true; shift ;;
            -y|--yes)        AUTO_YES=true; shift ;;
            -o|--output)     [[ $# -lt 2 ]] && { log_err "$1 requires a format"; exit 1; }; OUTPUT_FORMAT="$2"; shift 2 ;;
            -q|--quiet)      QUIET=true; shift ;;
            --no-color)      NO_COLOR=true; shift ;;
            -V|--version)    echo "cPanel TMP Manager v${VERSION}"; exit 0 ;;
            -h|--help)       show_help; exit 0 ;;
            -*)              log_err "Unknown option: $1 (use --help)"; exit 1 ;;
            *)               log_err "Unexpected argument: $1 (use --help)"; exit 1 ;;
        esac
    done

    [[ "$THRESHOLD" =~ ^[0-9]+$ ]] && (( THRESHOLD >= 0 && THRESHOLD <= 100 )) || { log_err "--threshold must be 0..100"; exit 1; }
    [[ "$AGE_HOURS" =~ ^[0-9]+$ ]] || { log_err "--age-hours must be a non-negative integer"; exit 1; }
    case "$OUTPUT_FORMAT" in
        table|json) ;;
        *) log_err "--output must be table or json"; exit 1 ;;
    esac
}

# =============================================================================
# Partition Telemetry & Hardening Audit
# =============================================================================
TMP_SOURCE="" TMP_SIZE="" TMP_USED="" TMP_AVAIL="" TMP_PCENT="0" TMP_IPCENT="0" TMP_FSTYPE=""
TMP_OPTS="" TMP_MODE="" TMP_HARDENED="false"

collect_tmp_stats() {
    read -r TMP_SOURCE TMP_SIZE TMP_USED TMP_AVAIL TMP_PCENT TMP_IPCENT TMP_FSTYPE <<< "$(
        df -h --output=source,size,used,avail,pcent,ipcent,fstype "$TMP_DIR" 2>/dev/null | tail -n 1
    )"
    TMP_PCENT="${TMP_PCENT%\%}"
    TMP_IPCENT="${TMP_IPCENT%\%}"
    [[ "$TMP_PCENT" =~ ^[0-9]+$ ]] || TMP_PCENT=0
    [[ "$TMP_IPCENT" =~ ^[0-9]+$ ]] || TMP_IPCENT=0

    TMP_MODE=$(stat -c '%a' "$TMP_DIR" 2>/dev/null || echo "unknown")
    TMP_OPTS=$(awk -v mp="$TMP_DIR" '$2 == mp {print $4; exit}' /proc/mounts 2>/dev/null || echo "inherited")
    [[ -z "$TMP_OPTS" ]] && TMP_OPTS="inherited"

    if [[ "$TMP_MODE" == "1777" && "$TMP_OPTS" == *noexec* && "$TMP_OPTS" == *nosuid* && "$TMP_OPTS" == *nodev* ]]; then
        TMP_HARDENED="true"
    else
        TMP_HARDENED="false"
    fi
}

cmd_status() {
    collect_tmp_stats
    local host alert_state="OK"
    host=$(hostname 2>/dev/null || echo "unknown")
    if (( TMP_PCENT >= THRESHOLD || TMP_IPCENT >= THRESHOLD )); then
        alert_state="ALERT"
    fi

    local top_items
    top_items=$(du -shx "${TMP_DIR}"/* "${TMP_DIR}"/.[!.]* 2>/dev/null | sort -hr | head -n 5 || true)

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        python3 - "$VERSION" "$host" "$TMP_DIR" "$TMP_SOURCE" "$TMP_FSTYPE" \
            "$TMP_SIZE" "$TMP_USED" "$TMP_AVAIL" "$TMP_PCENT" "$TMP_IPCENT" \
            "$TMP_MODE" "$TMP_OPTS" "$TMP_HARDENED" "$THRESHOLD" "$alert_state" <<'PYEOF'
import json, sys, datetime
(ver, host, mp, src, fs, sz, used, avail, pct, ipct, mode, opts, hard, thr, state) = sys.argv[1:16]
print(json.dumps({
    "version": ver,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "hostname": host,
    "mount_point": mp,
    "source": src,
    "fstype": fs,
    "size": sz,
    "used": used,
    "available": avail,
    "disk_used_pct": int(pct),
    "inode_used_pct": int(ipct),
    "permissions": mode,
    "mount_options": opts,
    "hardened_noexec_nosuid_nodev": hard == "true",
    "threshold_pct": int(thr),
    "status": state,
}, indent=2))
PYEOF
    else
        local st_col="$C_GREEN"
        [[ "$alert_state" == "ALERT" ]] && st_col="$C_RED"
        echo "================================================================================"
        echo " CPANEL TMP MANAGER v${VERSION} - [${host}]"
        echo "================================================================================"
        echo " Mount Point  : ${TMP_DIR} (${TMP_SOURCE}, ${TMP_FSTYPE})"
        echo " Disk Usage   : ${TMP_USED} / ${TMP_SIZE} (${TMP_PCENT}% used, ${TMP_AVAIL} avail) | Threshold: ${THRESHOLD}%"
        echo " Inode Usage  : ${TMP_IPCENT}%"
        echo " Permissions  : ${TMP_MODE} (expected: 1777)"
        echo " Mount Flags  : ${TMP_OPTS}"
        echo -e " Hardening    : $([[ "$TMP_HARDENED" == "true" ]] && echo "${C_GREEN}HARDENED (noexec,nosuid,nodev + 1777)${C_RESET}" || echo "${C_YELLOW}NOT FULL HARDENED (check noexec,nosuid,nodev)${C_RESET}")"
        echo -e " Health State : ${st_col}${alert_state}${C_RESET}"
        echo "--------------------------------------------------------------------------------"
        echo " Top Consumers in ${TMP_DIR}:"
        if [[ -n "$top_items" ]]; then
            echo "$top_items" | sed 's/^/   /'
        else
            echo "   (empty)"
        fi
        echo "================================================================================"
    fi

    [[ "$alert_state" == "ALERT" ]] && return 2
    return 0
}

# =============================================================================
# Safe Cleanup (Zero Downtime, Socket & Open-File Protection)
# =============================================================================
cmd_clean() {
    collect_tmp_stats

    if [[ "$FORCE" == false && "$TMP_PCENT" -lt "$THRESHOLD" && "$TMP_IPCENT" -lt "$THRESHOLD" ]]; then
        log_ok "/tmp usage (${TMP_PCENT}% disk / ${TMP_IPCENT}% inode) is below threshold (${THRESHOLD}%). Use --force to clean anyway."
        cmd_status
        return 0
    fi

    if [[ $EUID -ne 0 && "$DRY_RUN" == false ]]; then
        log_err "--clean requires root privileges (use sudo or --dry-run)."
        exit 1
    fi

    if [[ "$DRY_RUN" == false && "$AUTO_YES" == false && -t 0 ]]; then
        read -r -p "Clean files older than ${AGE_HOURS}h in ${TMP_DIR} and ${VAR_TMP}? [y/N]: " ans
        [[ "$ans" =~ ^[Yy]$ ]] || { log_info "Cancelled by user."; return 0; }
    fi

    local min_age=$(( AGE_HOURS * 60 ))
    local removed_count=0 skipped_open=0 freed_kb=0
    local dir f sz

    for dir in "$TMP_DIR" "$VAR_TMP"; do
        [[ -d "$dir" ]] || continue
        log_info "Scanning ${dir} for files older than ${AGE_HOURS}h (${min_age} min)..."

        while IFS= read -r -d '' f; do
            # Skip protected sockets, systemd private dirs, PHP/MySQL/LiteSpeed runtime files
            case "$f" in
                */mysql.sock*|*/*.sock|*/systemd-private-*|*/.ICE-unix/*|*/.X11-unix/*|*/.font-unix/*|*/hsperfdata_*|*/lshttpd/*|*/.cpanel*|*/sess_active*)
                    continue ;;
            esac

            # Skip files currently open by any process
            if command -v fuser >/dev/null 2>&1; then
                if fuser "$f" >/dev/null 2>&1; then
                    ((skipped_open++))
                    continue
                fi
            fi

            sz=$(du -sk "$f" 2>/dev/null | awk '{print $1}' || echo 0)
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[DRY-RUN] Would remove (${sz} KB): ${f}"
                ((removed_count++))
                ((freed_kb += sz))
            else
                if rm -f "$f" 2>/dev/null; then
                    ((removed_count++))
                    ((freed_kb += sz))
                    echo "$(date '+%Y-%m-%d %H:%M:%S') REMOVED (${sz}KB): ${f}" >> "$LOG_FILE" 2>/dev/null || true
                fi
            fi
        done < <(find "$dir" -mindepth 1 -xdev -type f -mmin "+${min_age}" -print0 2>/dev/null)
    done

    local freed_mb
    freed_mb=$(awk -v kb="$freed_kb" 'BEGIN { printf "%.2f", kb / 1024.0 }')

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        cat <<EOF
{
  "version": "${VERSION}",
  "action": "clean",
  "dry_run": ${DRY_RUN},
  "age_hours": ${AGE_HOURS},
  "files_removed": ${removed_count},
  "open_files_protected": ${skipped_open},
  "freed_mb": ${freed_mb}
}
EOF
    else
        local dry_tag=""
        [[ "$DRY_RUN" == true ]] && dry_tag=" (DRY-RUN)"
        echo "================================================================================"
        echo " CPANEL TMP MANAGER v${VERSION} - CLEANUP SUMMARY${dry_tag}"
        echo "================================================================================"
        echo " Age Filter           : > ${AGE_HOURS} hour(s)"
        echo " Files Removed        : ${removed_count}"
        echo " Open Files Protected : ${skipped_open}"
        echo " Space Reclaimed      : ${freed_mb} MB"
        echo "================================================================================"
    fi
}

# =============================================================================
# Safe Resize (tmpfs live remount OR cPanel /scripts/securetmp)
# =============================================================================
cmd_resize() {
    collect_tmp_stats

    if [[ $EUID -ne 0 && "$DRY_RUN" == false ]]; then
        log_err "--resize requires root privileges."
        exit 1
    fi

    if [[ "$TMP_FSTYPE" == "tmpfs" ]]; then
        if [[ -z "$RESIZE_SIZE" ]]; then
            if [[ -t 0 ]]; then
                read -r -p "Enter new tmpfs size (e.g. 2048M or 4G): " RESIZE_SIZE
            else
                log_err "Specify size for tmpfs resize, e.g.: --resize 2048M"
                exit 1
            fi
        fi
        [[ "$RESIZE_SIZE" =~ ^[0-9]+[MGmg]$ ]] || { log_err "Invalid size '${RESIZE_SIZE}' (expected e.g. 2048M or 4G)"; exit 1; }
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] Would run: mount -o remount,size=${RESIZE_SIZE} ${TMP_DIR}"
            return 0
        fi
        mount -o "remount,size=${RESIZE_SIZE}" "$TMP_DIR"
        log_ok "Resized tmpfs ${TMP_DIR} live to ${RESIZE_SIZE} (zero downtime)."
    else
        if [[ ! -x /scripts/securetmp ]]; then
            log_err "/scripts/securetmp not found and ${TMP_DIR} is not tmpfs (${TMP_FSTYPE})."
            exit 1
        fi
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] Would run cPanel /scripts/securetmp --auto"
            return 0
        fi
        if [[ "$AUTO_YES" == false && -t 0 ]]; then
            read -r -p "Run /scripts/securetmp --auto to rebuild ${TMP_DSK}? [y/N]: " ans
            [[ "$ans" =~ ^[Yy]$ ]] || { log_info "Cancelled by user."; return 0; }
        fi
        /scripts/securetmp --auto
        log_ok "cPanel securetmp completed."
    fi
}

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"
    init_colors

    case "$ACTION" in
        status) cmd_status; exit $? ;;
        clean)  cmd_clean;  exit $? ;;
        resize) cmd_resize; exit $? ;;
    esac
}

main "$@"
