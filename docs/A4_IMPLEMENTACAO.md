# A4 — rochas em lotes, interação física e persistência

**Checkpoint de entrada:** \`checkpoint/a3-functional-20261119\` → commit \`0b74e2ac01c65f48027e590bd22e2d86060287cc\`. A3 aprovada em testes nativos/SQLite e revisão funcional manual, mas EDIT-100 estrito, colisão do personagem e streaming sob carga continuam pendentes de medição.

## Arquitetura
- \`Terrain/RockInstancer\` é um \`VoxelInstancer\` nativo, filho do terreno. \`VoxelInstanceLibraryMultiMeshItem\`, ID fixo 100 e \`VoxelInstanceGenerator\` configuram densidade de ~0,016 rocha/m², altura e inclinação. Um \`SphereMesh\` low-poly evita assets externos. Geração, publicação e LOD continuam *exclusivamente* no Voxel Tools.
- \`item.persistent=true\`: quando uma rocha é removida pelo instancer, sua retirada estática é associada ao \`VoxelStreamSQLite\`. A ferramenta nativa \`remove_instances_in_sphere\` dispara a ação \`REMOVAL_BEHAVIOR_INSTANTIATE\` para converter apenas as rochas atingidas em \`RigidBody3D\` com colisão de esfera simplificada, massa, atrito e gravidade.
- \`RockManager\` controla somente os corpos **já promovidos**, com ≤24 corpos ativos em física no raio de 24 m, congelamento além de 32 m. Não há malha individual por rocha distante nem outro gerenciador de regiões.
- Os corpos promovidos têm ID por posição original quantizada em centímetros, proteção contra duplicatas e sidecar JSON por seed para posição, rotação, velocidades e estado de repouso. O sidecar é gravado temporariamente e renomeado; o VoxelStreamSQLite nativo continua responsável pelas alterações do terreno e pela marcação de instâncias estáticas removidas.
- Input: pressione \`F\` mirando o chão junto de uma rocha (até 24 m); edição SDF da A3 e \`Ctrl+S\` preservados. Automático: sidecar de corpos a cada 5 s, salvamento SQLite sob Ctrl+S. Evitar desligamento forçado durante gravações.

## Critérios
- A4-INSTANCER: código e cena nativos instanciados, contagem/estatística real, pelo menos 400 objetos **na área de 130 m**, após carregamento. Contador do motor, isoladamente, não qualifica essa área; verificação gráfica/espacial ainda é necessária.
- A4-PHYSICS: corpo físico cai, colide e repousa sobre terreno/fixture sem atravessar.
- A4-PROMOTE: disparo nativo remove a estática, corpo aparece na mesma posição e o total dinâmico é limitado. Sem duplicação ao reentrar/reabrir.
- A4-SAVE: sidecar persiste transform/velocidades e o VoxelStreamSQLite persiste a remoção da instância estática. Reabertura deve verificar os dois lados.
- STREAM-18/VIEW-130/PERF-60: executar cargas gráficas A2 sob rochas; sem gaps, atraso de rochas nem stutter. CI headless NÃO é gate gráfico.

## Local
\`\`\`powershell
cd C:\Dev\sandbox_v2_mvp_godotVoxel
git fetch origin
git switch --track origin/feat/a4-voxel-rock-instancing-physics-20261119
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a4-smoke-windows.ps1
& .\.tools\godot.exe --path .\godot
\`\`\`
A mesma DLL C++ da A3 é reutilizada. O CI verifica hashes Git dos arquivos nativos antes de restaurar o artefato aprovado da A3; se o C++ mudar, falha em vez de reutilizar uma DLL incorreta.

## Limitações
1. O motor escolhe os pontos estocasticamente por bloco/malha, de modo que o contador global \`debug_get_instance_counts\` pode incluir rochas fora do círculo de 130 m. A contagem qualificada da área e ausência de rochas flutuantes exigem inspeção espacial adicional.
2. O instancer fornece callback de remoção por esfera, não ID público de cada item antes da promoção. O ID é baseado no transform inicial quantizado; eventos em posições extremamente próximas precisam de revisão de colisão/duplicata.
3. A conexão entre salvamento nativo de remoções e o sidecar JSON não forma uma transação única; queda/crash no meio dos dois saves exige reconciliação em uma fase futura. Não reivindicar atomicidade entre arquivos.
4. Dinâmicas congeladas permanecem nos dados e podem ser reativadas, mas não voltam automaticamente à instância estática nativa. Isso evita reaparecimento duplicado, porém deve ser verificado sob trajetórias longas.
