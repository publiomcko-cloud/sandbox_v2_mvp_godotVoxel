# Sandbox V2 — MVP A | Godot + Voxel Tools + C++

**Estado:** especificação inicial; implementação, build e benchmarks ainda não iniciados.

## Objetivo

Validar do zero um sandbox 3D com terreno volumétrico SDF editável, cavernas, streaming contínuo, LOD, rochas procedurais com física básica e água com empuxo/arrasto. Este repositório é independente de projetos anteriores: nenhuma base de código é herdada.

## Stack proposta

- Godot 4.7.2 e Voxel Tools 1.7 (build nativa reproduzível, versões/commits fixados na implementação).
- C++20 para controladores e integração nativa; física Jolt e recursos de terreno/LOD do Voxel Tools.
- Windows como plataforma inicial de qualificação; benchmarks com renderização gráfica real.

## Aceite obrigatório

| Métrica | Requisito |
| --- | --- |
| Frame completo | 60 FPS; orçamento de até **16,7 ms por frame** |
| Deslocamento | **18 m/s** contínuos, sem regiões desaparecendo ou piscando |
| Horizonte visual | **130 m de raio**, 360°, com LOD, terreno, rochas e água |
| Edição | **até 100 ms**, do comando ao frame que apresenta a alteração |
| Física | Colisões, gravidade e atrito de rochas; empuxo/arrasto e interação com água |
| Persistência | Restaurar terreno editado e estados alterados dos objetos |

Não basta medir geração headless: a aprovação depende de percurso automatizado, métricas de CPU/GPU e inspeção visual em 1080p.

## Documentação

- [Especificação técnica do MVP A](docs/MVP_A_GODOT_VOXEL_TOOLS_CPP.md)
- [Contrato comum de requisitos e benchmarks](docs/CRITERIOS_COMUNS.md)

## Sequência inicial

1. Fixar dependências exatas e demonstrar compilação limpa da engine e extensão C++.
2. Criar o mundo SDF determinístico, cavidades, LOD e cobertura inicial.
3. Integrar edição local, colisão, rochas dinâmicas, água e persistência.
4. Automatizar percursos frios/quentes, editar durante movimento e medir frames apresentados.
5. Corrigir somente gargalos reproduzidos por evidências; registrar resultados e limites.

**Regra de continuidade:** manter geometria válida visível até a substituta estar pronta; não criar um segundo sistema concorrente de terreno ou desmontar regiões antes de concluir os novos recursos. Descarga e publicação devem ser limitadas por orçamento, sem bloquear o frame.

## Execução

Ainda não há executável ou comandos de build validados. Eles serão documentados após a primeira compilação reproduzível.
