# Sandbox V2 — MVP A | Godot + Voxel Tools + C++

**Estado:** A0 build/API/smoke aprovados no CI e renderização local confirmada; A1 em implementação. Metas de desempenho e cobertura real ainda não qualificadas.

MVP independente de sandbox volumétrico 3D com Godot 4.7.2 + Voxel Tools 1.7 integrado e lógica nativa em C++20. Meta final: 60 FPS/16,7 ms por frame completo, movimento contínuo de 18 m/s sem lacunas, raio visual efetivo de 130 m em 360°, edição visível <=100 ms, rochas físicas, água básica e persistência.

## Documentos
- [Especificação técnica do MVP A](docs/MVP_A_GODOT_VOXEL_TOOLS_CPP.md)
- [Contrato comum de requisitos e benchmarks](docs/CRITERIOS_COMUNS.md)
- [A0: bootstrap, execução e gates](docs/A0_IMPLEMENTACAO.md)
- [A1: mundo SDF, cavernas e LOD](docs/A1_IMPLEMENTACAO.md)
- [A2: rotas determinísticas, streaming e telemetria](docs/A2_IMPLEMENTACAO.md)
- [A3: edição C++, SQLite e teste de reabertura](docs/A3_IMPLEMENTACAO.md)

## A0 Windows (PowerShell)
Pré-requisitos: MSVC Build Tools x64, Python 3.12, Git e SCons 4.10.0.
```powershell
py -3.12 -m pip install scons==4.10.0
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-windows.ps1
& .\.tools\godot.exe --path .\godot
```
O bootstrap usa o editor Godot+Voxel Tools oficial do release v1.7, confere SHA-256, baixa `godot-cpp` em commit fixo, gera `extension_api.json` no editor **customizado** e compila `native/` contra esta API. CI inclui verificação estática e smoke headless; **não** classifica teste headless como 60 FPS gráfico.

A1 usa `VoxelGeneratorGraph` determinístico para relevo, túnel curvo subterrâneo e acesso vertical em aproximadamente (x=38,z=0), com um único `VoxelLodTerrain` + Transvoxel. Solicita 192 unidades de view distance e 4 LODs; 130 m efetivamente visíveis e costuras sem falhas precisam de teste gráfico, não de smoke headless. W/A/S/D movem a 18 m/s, E/Q controlam altura; clique esquerdo captura o mouse e Escape libera. Este observador não possui colisão.

Princípios: um único sistema de terreno/LOD, geometria válida retida até substituição, recursos não antecipam terreno, tarefas e publicação limitadas por orçamento e qualificações por benchmark gráfico real. Ver detalhes nos documentos de arquitetura.

## A2 — benchmark gráfico reproduzível (experimental)
Sem substituir o streamer do Voxel Tools. Registra rotas a 18 m/s e métricas de frame/filas/meshing (não confundir intervalos CPU com GPU+present).

\`\`\`powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a2-benchmark-windows.ps1 -Route out_and_back_18mps_300s -Duration 300 -Warmup 45
\`\`\`

JSONL e resumo aparecem em \`reports/generated/\`. Para capturas periódicas, inclua \`-Capture\`, em execução separada. A aprovação visual 18m/s e 130m efetivos ainda requer inspeção dos resultados.


## A3 — edição nativa e persistência
Novo C++ exige recompilação da GDExtension após mudar para a branch A3:
\`\`\`powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-windows.ps1 -SkipDownload
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a3-smoke-windows.ps1
& .\.tools\godot.exe --path .\godot
\`\`\`
No jogo, clique para capturar mouse, botão esquerdo remove terreno e direito adiciona; segure até 10Hz, Ctrl+S salva, Esc libera mouse. SQLite padrão: \`user://worlds/a3_v1_seed_20261119.sqlite\`. O smoke usa banco temporário isolado e verifica reabertura em novo processo. A edição aceita somente áreas LOD0 carregadas; falhas não executam brush parcial. **Latência até pixel realmente apresentado e colisão pós-edição ainda exigem qualificação gráfica.**
