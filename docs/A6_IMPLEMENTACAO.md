# A6 — A/B Voxel Tools CPU versus GPU, blocos de malha 16/32

Checkpoint imutável de entrada: \`checkpoint/a5-functional-20261119\`, commit \`0c3fee959576d0a1faec9ceecffb4b132a65558b\`, A0–A5 funcionalmente aceitos no MVP, com água global em y=0 registrada para pós-MVP (issue #7). **Não altera o jogo padrão nem promove otimizações especulativas**.

## Restrições técnicas verificadas

A5 usa \`gl_compatibility\` (OpenGL), mas \`VoxelLodTerrain.use_gpu_generation\` do Voxel Tools 1.7 exige Vulkan e gerador compatível. A6 inicia cada **braço gráfico** em \`--rendering-method forward_plus --rendering-driver vulkan\`, inclusive o braço **CPU**. Um braço CPU OpenGL pode existir como controle histórico, mas não é comparação CPU-vs-GPU válida. O \`VoxelGeneratorGraph\` original (mesmos três FastNoiseLite2D, seed e operações SDF) é preservado em todas as variantes.

| Perfil | Generator | Mesh block | LOD | View distante | Renderer |
|---|---|---:|---:|---:|---|
| \`cpu16\` | CPU | 16 | 4/48m | 192m | Forward+ Vulkan |
| \`gpu16\` | GPU solicitada | 16 | 4/48m | 192m | Forward+ Vulkan |
| \`cpu32\` | CPU | 32 | 4/48m | 192m | Forward+ Vulkan |
| \`gpu32\` | GPU solicitada | 32 | 4/48m | 192m | Forward+ Vulkan |

A mudança é aplicada à cena \`PackedScene.instantiate()\` **antes** de \`root.add_child(world)\`, portanto antes da publicação dos chunks, nunca em mundo já ativo. Nenhuma alteração no editor/scene principal, no C++, no banco SQLite ou no sistema de streaming. O voxel perto do player permanece 1 m; **não** alegar 0,5 m.

O GPU backend usa compute shaders separados e pode ter custo de compilação particularmente elevado devido a FastNoiseLite. A marca \`use_gpu_generation=true\` é uma intenção de configuração, **não prova de dispatch em GPU**. O VoxelEngine coleta tarefas GPU e o CI exige **execução gráfica real** para GPU. A equivalência geométrica CPU/GPU também precisa ser testada em gráfico/Vulkan; o runner headless não a qualifica.

## Executar campanha em GPU Windows

\`\`\`powershell
cd C:\Dev\sandbox_v2_mvp_godotVoxel
git fetch origin
git switch --track origin/feat/a6-cpu-gpu-ab-mesh-blocks-20261119

# Exploração inicial com perfil individual (não qualifica A6)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a6-run-windows.ps1 -Profile cpu16 -Route out_and_back_18mps_300s -Duration 30 -Warmup 45
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a6-run-windows.ps1 -Profile gpu16 -Route out_and_back_18mps_300s -Duration 30 -Warmup 45

# Campanha com instrumentação idêntica e 3 repetições para cada perfil:
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a6-run-windows.ps1 -Campaign -Repeats 3 -Route out_and_back_18mps_300s -Duration 300 -Warmup 45
\`\`\`

**Importante:** o benchmark gráfico exige sessão Windows interativa com Vulkan em pleno funcionamento, não apenas runner serviço/headless. O jogo interativo padrão permanece A5 em OpenGL. O próprio script bloqueia GPU/headless e incompatibilidade de renderer. Perfis gráficos usam resolução 1920×1080; não alterar DPI, driver, VSync ou configurações entre braços. A ordem de braços é alternada nas repetições para mitigar efeitos térmicos.

Arquivos por execução: \`reports/generated/a6/experiment-.../{cpu16,gpu16,cpu32,gpu32}_repNN/a2_*.jsonl|json\`; \`manifest.json\` e \`a6_comparison.json\` se processado. \`scripts/a6_compare.py\` agrupa runs com mesmos seed, duração, warmup, renderer, drive e view-distance:
\`\`\`powershell
python .\scripts\a6_compare.py .\reports\generated\a6\experiment-YYYYMMDD-HHMMSS-PID
\`\`\`
O comparador nunca aprova automaticamente uma otimização. A coleta inclui A2 frame-start intervals p50/p95/p99/p99,9/máximo, contadores de fila, bloco e VRAM interna do VoxelEngine, e medidas CPU/GPU por viewport com instrumentação idêntica. **Tempos da viewport não são latência total CPU+GPU+present.** Frames do SO, stutter gráfico e render real precisam de inspeção e captura externa apropriada.

Para capturas PNG, execute um braço *isoladamente* com \`-Capture\`; o overhead é diferente e esses runs nunca devem entrar na comparação de performance.

## CI automatizado

\`scripts/a6-smoke-windows.ps1\` executa \`cpu16\` e \`cpu32\` headless por apenas 2 s cada para validar configuração/relatórios e regressões A0–A5. Como o headless não possui \`RenderingDevice\`, \`gpu16\`/ \`gpu32\` **não são executados** e ficam \`NOT_QUALIFIED\`. Mesmo com Actions SUCCESS, nenhum número de performance headless é usado para aprovar/recusar a GPU.

## Gatilhos para decisão

1. Comparação gráfica de \`cpu16↔gpu16\` e \`cpu32↔gpu32\`, três corridas idênticas por perfil/rota, incluindo CPU/GPU GPU time, p99 e memória; confirmar dispatch real e compilação de shader, não apenas flag.
2. \`cpu16↔cpu32\` e \`gpu16↔gpu32\`: sem diminuição de horizonte/qualidade, EDIT-100 pós-mudança de bloco, colisão e costura LOD.
3. STREAM-18, VIEW-130, PERF-60: sem gaps nem stutter nas rotas canônicas; não aceitar ganho de geração isolado se piorar p99 do frame completo.
4. Persistência A3, rochas A4, água A5 sem regressão visual; nenhum resultado C++/GPU é promovido até qualificar esses gates.

**Decisão inicial A6 = BASELINE_RETAINED / NO_CANDIDATE_PROMOTED**. A6 oferece a campanha A/B para medição, sem presumir que GPU será melhor. Sem métricas gráficas de ambos os braços, o gate A6-GPU permanece \`NOT_QUALIFIED\`.

Fontes: documentação Voxel Tools v1.7 \`VoxelLodTerrain.use_gpu_generation\`, guia Performance (backend GPU Vulkan, FastNoiseLite e custo de compilação), Godot RenderingServer sobre timings por viewport.
