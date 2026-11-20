# A7 — GitHub Actions gráfico automatizado no Windows

Workflow: .github/workflows/a7-resources-interactive.yml. Branch: exp/a7-resource-utilization-20261120. PR #12 draft. Teste isolado: nenhuma mudança no código da A5.

## Bloqueio identificado

O Actions #44766942607 executou em DESKTOP-T0U6S55, com runner em C:\actions-runner. O preflight confirmou Session 0, onde o serviço Windows não possui desktop gráfico interativo. Não classificar execuções de Session 0 como benchmark da GPU/visual.

## Configuração única no PC do runner

**Executar na máquina DESKTOP-T0U6S55, com uma sessão Windows iniciada, PowerShell "Executar como administrador".** O comando muda o runner selecionado do serviço para uma tarefa interativa automática ao logon. Ele não cria conta, não armazena senha, não ativa logon automático. O serviço é colocado em inicialização manual e pode ser restaurado. O script aborta se detectar um job do runner em andamento.

    cd C:\Dev\sandbox_v2_mvp_godotVoxel
    git fetch origin
    git switch exp/a7-resource-utilization-20261120
    git merge --ff-only origin/exp/a7-resource-utilization-20261120
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a7-configure-interactive-runner-windows.ps1 -RunnerRoot C:\actions-runner

Se o repositório não estiver clonado nesse computador, copie o script da branch experimental para a máquina antes de executar. Verifique que C:\actions-runner\run.cmd e C:\actions-runner\.runner existem. A sessão deve permanecer conectada e com desktop 1920x1080 ativo durante o teste. Não bloquear a tela; deixar energia e monitor estáveis.

O runner configurado passa a rodar sob a conta Windows interativa, com acesso aos arquivos que essa conta consegue acessar, e não mais sob a conta isolada do serviço. **Utilizar apenas workflows e código de confiança; evite PRs externos não confiáveis.** A mudança afeta também os outros repositórios desse runner e sua disponibilidade dependerá do logon do usuário. Para isolamento mais forte, configurar um runner dedicado e uma conta Windows restrita.

## Executar campanha automaticamente

Após a configuração única, usar GitHub Actions: A7 Windows graphical resource A-B → selecionar execução #44766942607 → Re-run jobs (ou disparar novo push revisado na branch experimental). O job realiza preparação do Godot, os oito perfis A/B, consolida métricas e publica artefato, inclusive em falhas após preflight.

- Runtime alvo: Godot 4.7.2/Voxel Tools 1.7, GL Compatibility, 1920x1080.
- Cenário: shoreline, 60s + 45s de warmup, seed 20261119, dois repeats, ordem invertida.
- Perfis: VSync ON auto, VSync OFF auto, VSync OFF threads médias, VSync OFF threads altas (se CPU permitir).
- Artefatos: reports/generated/a7-resources/** e reports/generated/a7-interactive-preflight.json.
- CI não concede PASS formal para PERF-60, VIEW-130 e EDIT-100 sem evidências de pixels e apresentação.

## Restaurar modo serviço

Na mesma máquina, PowerShell elevado e desktop iniciado:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a7-configure-interactive-runner-windows.ps1 -RunnerRoot C:\actions-runner -RestoreService

Isso remove a tarefa interativa e restaura o serviço do GitHub runner para inicialização automática.
