# Sandbox V2 — MVP A | Godot + Voxel Tools + C++

**Estado:** A0 bootstrap em implementação; nenhuma meta de desempenho qualificada.

MVP independente de sandbox volumétrico 3D com Godot 4.7.2 + Voxel Tools 1.7 integrado e lógica nativa em C++20. Meta final: 60 FPS/16,7 ms por frame completo, movimento contínuo de 18 m/s sem lacunas, raio visual efetivo de 130 m em 360°, edição visível <=100 ms, rochas físicas, água básica e persistência.

## Documentos
- [Especificação técnica do MVP A](docs/MVP_A_GODOT_VOXEL_TOOLS_CPP.md)
- [Contrato comum de requisitos e benchmarks](docs/CRITERIOS_COMUNS.md)
- [A0: bootstrap, execução e gates](docs/A0_IMPLEMENTACAO.md)

## A0 Windows (PowerShell)
Pré-requisitos: MSVC Build Tools x64, Python 3.12, Git e SCons 4.10.0.
```powershell
py -3.12 -m pip install scons==4.10.0
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\bootstrap-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-windows.ps1
& .\.tools\godot.exe --path .\godot --editor
```
O bootstrap usa o editor Godot+Voxel Tools oficial do release v1.7, confere SHA-256, baixa `godot-cpp` em commit fixo, gera `extension_api.json` no editor **customizado** e compila `native/` contra esta API. CI inclui verificação estática e smoke headless; **não** classifica teste headless como 60 FPS gráfico.

A cena temporária tem terreno plano `VoxelLodTerrain`, mesher Transvoxel e um `VoxelViewer`; W/A/S/D e E/Q movem câmera livre a 18 m/s sem física. É apenas o primeiro teste de integração. Relevo SDF, cavernas e horizonte completo pertencem à A1.

Princípios: um único sistema de terreno/LOD, geometria válida retida até substituição, recursos não antecipam terreno, tarefas e publicação limitadas por orçamento e qualificações por benchmark gráfico real. Ver detalhes nos documentos de arquitetura.
