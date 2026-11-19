# A6B — Diagnóstico dirigido das cinco sondas incompletas em mesh32

**Base:** A6 no commit add1167c6b5f2b9e8b41503135d8a0b5c8de7027, a partir de A5 funcional (0c3fee95). Não promove GPU nem blocos de 32, não altera streaming/LOD, física, água, edições, C++ ou o mundo padrão. Esta fase é uma investigação isolada, não uma regressão de desempenho.

## Dados reais que motivaram A6B

O ZIP enviado pelo operador, reportsA6.zip, contém uma campanha gráfica Vulkan de 12 sessões, três de cada CPU16/GPU16/CPU32/GPU32, duração 300s após 45s de aquecimento, sempre com seed 20261119 e 18m/s. Em **todas as seis sessões mesh32**, a sonda A2 em raio 130m marcou 7/8 em cinco amostras; ambas as variantes mesh16 tiveram 8/8 nos 900 pontos amostrados em cada grupo.

| Tempo A6 (s) | X do player (m) | Direção | Observação |
|---:|---:|---|---|
| 7.004 | 126.07 | ida | AABB de 4m pode cruzar borda de 128m |
| 64.001 | 1152.01 | ida | centro perto de borda |
| 135.005 | 2430.08 | ida | AABB na borda |
| 236.009 | 1151.84 | volta | mesma borda com direção contrária |
| 250.016 | 899.72 | volta | sonda no limite de grade |

**Padrão espacial verificado:** 32 voxels por bloco de malha × 4 (LOD2) = **128 metros por bloco de malha**. Em todos os cinco pontos, ao menos uma das oito AABB sondadas (4×16×4 m) atravessa uma borda da grade 128m. Entretanto, em uma das três execuções CPU32 também houve **35 amostras sem falha que cruzavam a grade**: a correlação não determina causalidade e não demonstra lacuna visível.

A sonda original retorna true se *uma única AABB inteira* estiver malhada no LOD2 **ou** LOD3. Uma AABB que cruza duas regiões usando LODs diferentes pode falhar mesmo com cobertura por partes; alternativamente, pode haver um bloco realmente ausente. A6B irá distinguir as possibilidades.

## Instrumentação A6B

- Mesma cena e mesma seed, sem modificar o VoxelLodTerrain. Perfil CPU16 e CPU32 aplicado **antes** de entrar na SceneTree.
- Reposiciona o observador na coordenada exata aproximada de cada um dos cinco pontos e mede no primeiro frame e após 3s de atualização. Isto distingue um falso negativo persistente de carregamento transitório; **teleporte e espera não reproduzem a rota contínua de 300s**.
- Para cada uma das oito direções, grava o resultado original LOD2/3 para a AABB inteira, resultado por todos os LOD0–3, quatro sub-AABBs 2×16×2m com disponibilidade por LOD e se a consulta cruza fronteira de 128m.
- Caso a AABB original falhe enquanto as quatro partes estão malhadas em LODs mistos, há evidência de **falso negativo da consulta composta** (não de pixels). Se qualquer sub-AABB estiver indisponível em todos os LODs, permanece potencial cobertura não pronta, também não prova imagem ausente.
- Em janela gráfica Forward+ Vulkan, captura PNGs cardeais para comparação CPU16/CPU32. A coleta de imagens é separada de benchmarks de performance e **não é evidence for PERF-60**. Visualmente comprovar terreno/rochas/água completos no raio de 130m exige revisar as imagens e ângulos correspondentes, com cautela sobre perspectiva/oclusão.

## Execução curta Windows (não exige repetir 69min)

\`\`\`powershell
cd C:\Dev\sandbox_v2_mvp_godotVoxel
git fetch origin
git switch --track origin/diag/a6b-mesh32-probe-boundaries-20261119

# Diagnóstico gráfico dos cinco pontos para CPU16/CPU32, com PNGs:
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\a6b-run-windows.ps1 -Capture
\`\`\`

O script gera dois relatórios JSON detalhados, resumo CSV, auditoria geométrica e até 40 screenshots em \`reports/generated/a6b/diagnostic-...\` e **não toca nos saves interativos**. Não é preciso recompilar C++.

No CI, rodar apenas t007, CPU16 e CPU32, headless, para provar integração da ferramenta; prints e resultados headless **não substituem** screenshots nem a avaliação da rota em movimento. Se os cinco pontos passarem após espera estacionária, realizar uma captura curta em **movimento real a 18m/s**, mirando as direções suspeitas, antes de classificar como artefato da sonda.

## Critérios de decisão

- Se CPU32 apresenta cobertura por quadrantes enquanto a AABB completa falha, corrigir a instrumentação A2 para agregar subáreas por LOD sem esconder lacunas. Repetir a evidência gráfica curta, não a campanha inteira.
- Se CPU32 realmente deixa subáreas incompletas sob carga ou aparecem buracos em imagem, manter CPU16; medir dependência de LOD/bloco e consistência de carregamento.
- Revalidar EDIT-100 após qualquer troca de block size; edição mais lenta ou colisor desatualizado **reprova a promoção**, mesmo que p99 de frame melhore.
- Nenhum dado headless, teleporte, gráfico de fila ou amostra de malha autoriza PERF-60, STREAM-18, VIEW-130 ou EDIT-100 automaticamente.

**Estado inicial:** BASELINE_A5_CPU16_RETAINED / A6B_DIAGNOSTIC_PENDING.
