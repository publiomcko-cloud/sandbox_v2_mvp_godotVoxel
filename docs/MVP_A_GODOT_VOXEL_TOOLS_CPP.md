# MVP A — Godot 4.7.2 + Voxel Tools 1.7 + C++

Status: **especificação de implementação do zero; não implementado**. 18/11/2026.
Critérios comuns e testes: `CRITERIOS_COMUNS.md`. Repositório próprio, novo e independente: `sandbox_v2_mvp_godotVoxel`.

## Proposta de validação

Comprovar que um motor com streaming volumétrico, LOD, meshing, edição e persistência nativos oferece o comportamento exigido sem criar um sistema paralelo de regiões. **Não** reimplementar o terrain streaming, surface extraction, LOD e um segundo compositor de geometria antes de medir o módulo pronto.

## Stack congelada na primeira baseline

- Godot **4.7.2** custom build com Voxel Tools **1.7** nativo (módulo) ou build compatível reproduzível; pinar artefato e commit. Export templates de Windows devem ser compatíveis. GDExtension alternativa se módulos da versão-alvo mostrarem problema comprovado.
- C++20 para lógica própria através de uma GDExtension `godot-cpp` compatível com a ABI da build selecionada; uso mínimo de scene scripts de integração. SCons/CMake com preset Release/RelWithDebInfo e símbolos; CI compila e executa smoke/headless.
- `VoxelLodTerrain`, `VoxelGeneratorGraph` para SDF base e cavernas, `VoxelMesherTransvoxel`, `VoxelViewer`, `VoxelStreamSQLite`, `VoxelInstancer` + `MultiMesh`, Jolt Physics, `RigidBody3D`, `CharacterBody3D`, `Area3D`.
- Versão inicial mede CPU generator e depois `use_gpu_generation` como configuração A/B, apenas em grafo compatível e Vulkan. GPU do Voxel Tools gera blocos, **não** implica renderização end-to-end residente em GPU.

## Organização sugerida

```
sandbox_v2_mvp_godotVoxel/
  README.md
  third_party.lock
  godot/project.godot
  godot/scenes/main.tscn
  godot/resources/terrain_generator.tres
  godot/resources/voxel_stream.tres
  godot/assets/shaders/water.gdshader
  native/CMakeLists.txt
  native/src/WorldController.cpp
  native/src/PlayerController.cpp
  native/src/TerrainEditController.cpp
  native/src/RockPhysicsController.cpp
  native/src/WaterPhysicsController.cpp
  native/src/Telemetry.cpp
  tests/scenarios/
  tests/benchmark_runner.cpp
  reports/
```

## Subsistemas

**Terreno.** Um único `VoxelLodTerrain` com grafo SDF determinístico, colinas, vales, caverna e canal/área inundada. Começar com 4 níveis de LOD e 16 voxels por bloco de malha para manter edição barata; medir 32 voxels para reduzir churn. Ajustar `lod_distance`, `view_distance` e `VoxelViewer` por cobertura efetivamente renderizada. Não assumir correspondência 1:1 de `view_distance` com raio geométrico de 130m; teste de cobertura decide. Preferir uso de recursos do Voxel Tools para costura LOD sem implementar meshers próprios.

**Streaming.** Uma política simples: núcleo com prioridade por distância, frente de movimento (até 36 m de prefetch adicional) e retenção limitada de recursos recentes. Não construir controlador separado que substitua malhas/cena do Voxel Tools. Observar picos em destruição de buffers: a documentação admite que remover muitas pequenas malhas pode bloquear o frame no Vulkan. Medir `mesh_block_size=16` versus 32, distâncias e velocidade, além de contagem de buffers destruídos/frame. Não aceitar redução da cobertura de 130m como falso ganho.

**Edição.** C++ dispara `VoxelTool` com `do_sphere` e `mode` adição/subtração quando `is_area_editable()` é verdadeiro; raio inicial 1,5m, 10 Hz, eventos timestampados. Medir do clique à mudança VISÍVEL, não somente retorno da API. Garantir que reprocessar colisor não congele o frame. Persistir blocos editados em `VoxelStreamSQLite`; fechar o mundo apenas após drenagem da fila de save (salvamento de terreno é assíncrono). Testar borda LOD/bloco.

**Rochas.** `VoxelInstancer` para rochas estáticas distante, com LOD e posicionamento coerente com SDF. Ao entrar em interação (~24–32m) promover somente rochas selecionadas/ativas para `RigidBody3D` com shape convexo simplificado, gravidade, atrito e amortecimento. Quando em repouso e fora do raio, despromover com salvamento de transform/estado. Evitar uma cena por rocha do horizonte; manter render em `MultiMesh`. Persistir alterações via stream/estado local; testar que não se duplicam nem desaparecem na transição.

**Água.** MVP de água como superfície estática nível y=0 e curso simples com volume detectável (`Area3D`), shader de ondas pequenas, forças de empuxo `rho*g*V_submerso`, arrasto e velocidade de corrente prescrita. Rochas densas afundam, objeto leve de teste flutua, player recebe gravidade/arrasto adaptativos na imersão. Não criar uma simulação CFD. Costa se resolve por profundidade do terreno, sem exigir uma malha de água por chunk que seja recriada junto com o terreno. Se uma escavação abaixo de y=0 ocorrer, testar cobertura no novo volume; estado visual e físico devem concordar.

**Observabilidade.** Telemetria C++ leve e desativável, medidas CPU+GPU e contagem de voxels/blocos, colisores, MeshInstances, rock bodies, fps/frame p99, alocações, fila de requests e saves; logs CSV/JSONL por evento. A instrumentação A/B deve ser idêntica.

## Execução incremental e gates

| Fase | Trabalho | Gate antes de prosseguir |
|---|---|---|
| A0 | Build Godot+Voxel Tools+GDExtension, render e CI Windows | Reprodutibilidade e 60fps de cena trivial |
| A1 | Um mundo SDF com cavernas, LOD e 130m visuais | Zero seam, efetiva cobertura 360° |
| A2 | Streaming a 18m/s e rota de retorno | Zero lacunas/piscadas em captura real; p99 e buffer churn registrados |
| A3 | C++ edição add/sub, limite 100ms e save | Edição 100ms inclusive bordas; reabertura correta |
| A4 | Rochas batched / rigid bodies próximos | Sem duplicação, gravidade e colisão estáveis |
| A5 | Água básica, nado, empuxo, costa | Efeito físico demonstrável; sem corte/flash ao editar |
| A6 | A/B nativo CPU/GPU generator, ajustes de LOD/blocos | Avaliar por P99 total, não por tempo de geração isolado |
| A7 | Bateria completa conforme contrato comum | PASS/FAIL explícito para cada meta |

## Hipóteses eliminatórias

- O módulo pode falhar no limite 16,7ms por custo de alocação/destruição de malhas Vulkan (problema documentado). Não esconder com redução de distância ou velocidade. Se persistente, classificar MVP A como FAIL em PERF-60/STREAM-18.
- `use_gpu_generation` depende do grafo e Vulkan, e pode não acelerar o caminho de edição/meshing/collider. Registrar tempo de frame completo com e sem essa opção.
- `VoxelInstancer` ao mudar LOD/terreno editado pode apresentar desalinhamento; escolher LOD por objeto e/ou persistência, medir visualmente.
- 100ms do clique ao frame apresentado talvez não seja alcançável em blocos 32; reversão para bloco 16 ou restrição do brush deve ser testada, não assumida.

## Done

Build Windows Release reproduzível; personagem a 18m/s, terreno 130m, cavernas, água e rochas físicas, edições add/sub persistentes com indicador de 100ms, artefatos de benchmark com logs e vídeos; resultados sem lacunas de cobertura e relatório honesto de limitações.

Fontes: https://voxel-tools.readthedocs.io/en/latest/api/VoxelLodTerrain/ ; https://voxel-tools.readthedocs.io/en/latest/performance/ ; https://voxel-tools.readthedocs.io/en/latest/streams/ ; https://voxel-tools.readthedocs.io/en/latest/instancing/ ; https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html ; https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/gdextension_cpp_example.html