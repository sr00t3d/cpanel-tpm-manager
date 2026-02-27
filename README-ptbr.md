# 🛠️ TMP Manager for cPanel

Readme: [Português](README.md)

![License](https://img.shields.io/github/license/sr00t3d/cpanel-tpm-manager)
![Shell Script](https://img.shields.io/badge/language-Bash-green.svg)

<img width="700" src="tmp-manager.webp" />

Este script Bash foi desenvolvido para monitorar, limpar e redimensionar a partição `/tmp` em servidores que utilizam o painel de controle **cPanel/WHM**. Ele lida tanto com partições virtuais (**tmpfs**) quanto com arquivos de loopback físicos (**tmpDSK**).

## ✨ Funcionalidades

* **Monitoramento em Tempo Real:** Verifica o uso atual da `/tmp` e exibe informações detalhadas.
* **Alertas de Limite:** Identifica automaticamente se o uso ultrapassou 80% (ou o valor configurado).
* **Limpeza Inteligente:** Utiliza o `tmpwatch` para remover arquivos com mais de 12 horas de inatividade.
* **Backup de Segurança:** Cria um backup completo dos arquivos da `/tmp` antes de redimensionar (em sistemas tmpfs).
* **Gerenciamento de Serviços:** Interrompe e reinicia automaticamente o MySQL/MariaDB para evitar travamentos de arquivos (file locks) durante a desmontagem.
* **Redimensionamento Automatizado:** Suporta o comando `/scripts/securetmp` nativo do cPanel.

---

## 🚀 Requisitos

* **Sistema Operacional:** CloudLinux / AlmaLinux / Rocky Linux / CentOS (com cPanel).
* **Privilégios:** Acesso de usuário **root**.
* **Dependências:** * `tmpwatch` (geralmente pré-instalado no cPanel).
* `systemd`.

---

## 🔒 Segurança e Boas Práticas

O script aprimorado com as seguintes camadas de segurança:

1. **Root Check:** Impede a execução por usuários sem privilégios.
2. **Lazy Unmount (`-l`):** Evita que o script trave caso processos ainda estejam tentando acessar a partição.
3. **Preservação de Atributos:** O comando `cp -a` garante que as permissões especiais do `/tmp` (Sticky Bit) sejam mantidas no backup.
4. **Logging:** Todas as ações de limpeza são registradas em `/var/log/tmp-manager.log`.

---

## 📖 Como Usar

1. **Crie o arquivo no servidor:**
```bash
nano /root/tmp-manager.sh

```

2. **Cole o código do script e salve.**
3. **Dê permissão de execução:**
```bash
chmod +x /root/tmp-manager.sh

```

4. **Execute o script:**
```bash
./root/tmp-manager.sh

```

---

## 🏗️ Estrutura do Script

| Variável | Descrição |
| --- | --- |
| `TMP_ALERT_ENABLED` | Define se o script deve sugerir correções baseado no uso (Default: `true`). |
| `ALERT_THRESHOLD` | Porcentagem de uso que dispara o alerta (Default: `80`). |
| `LOG_FILE` | Local onde os logs do `tmpwatch` são salvos. |
| `BACKUP_DIR` | Diretório temporário em `/root` para salvaguarda de arquivos. |

---

## ⚠️ Aviso Legal

Este script realiza operações críticas de nível de sistema (montagem/desmontagem de partições e reinicialização de banco de dados). **Sempre valide o backup** antes de confirmar operações de escrita e evite rodar o redimensionamento em horários de pico de tráfego, pois o MySQL/MariaDB será reiniciado.

## 📚 Tutorial Detalhado

Para um guia completo passo a passo, confira meu artigo completo:

👉 [**Corrija de forma segurança /tmp em servidor cPanel**](https://perciocastelo.com.br/blog/secure-tmp-properly-on-a-cpanel-server.html)

## Licença 📄

Este projeto está licenciado sob a **GNU General Public License v3.0**. Veja o arquivo [LICENSE](LICENSE) para detalhes.
