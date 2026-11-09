# Regressão da ignição

Executar com Python e `lupa` instalado:

```powershell
python tests/test_engine_flow.py
```

O teste executa os módulos completos `engine_control`, `vehicle_lock`,
`ignition_engine` e `vehicle_init` em Lua 5.4. As natives GTA, o inventário,
a rede e os callbacks do servidor são simulados; não valida a física do FiveM.
As chamadas de partida só passam a informar motor ligado após um atraso,
e callbacks podem responder depois de outro comando do jogador.

Cobre partida/desligamento, chave na ignição com motor parado, autorização
atrasada, expiração durante a partida, ausência de controle de rede, saída,
troca de veículo, controle remoto e reconstrução do inventário.
Também compila os arquivos Lua de execução, substituindo apenas os hashes
FiveM entre crases por números para o parser padrão. Snippets de instalação
não são scripts independentes e não entram nessa checagem.

## Conferência dentro do jogo

Após reiniciar `pr_carkeys`, testar com chave válida e veículo em condições:

1. Ligar com Z e confirmar que permanece ligado.
2. Desligar com Z e ligar novamente com a chave já na ignição.
3. Parar e sair imediatamente; repetir após aguardar alguns segundos.
4. Reentrar sem acelerar; confirmar que mantém o motor já ligado.
5. Repetir com partida remota e com uso do item chave.
6. Testar chave em bolsa, chave temporária e placa falsa.
7. Confirmar que motorista sem chave continua bloqueado.

Com `Config.Debug = true`, cada escrita do motor feita pelo PR Carkeys
registra `[Engine]`, o motivo, veículo e estado solicitado. Se a partida
não for confirmada em três segundos, o F8 registra combustível, saúde do
motor e estado de condução mesmo sem debug. Isso permite distinguir uma
negação de chave de um desligamento imposto por outro recurso.

## Revisão da aceleração ao sair (2026-09-16)

- Removido o ciclo que religava motores de veículos vazios. A saída passa a
  usar a flag do ped `LeaveEngineOnWhenExitingVehicles` (241), restaurando o
  valor anterior ao deixar o banco ou parar o recurso. Não altera RPM, torque,
  freio, velocidade ou acelerador.
- Referência nativa: https://github.com/citizenfx/natives/blob/master/PED/SetPedConfigFlag.md
- No PR Mileage, a retomada após `stall` só ocorre com o mesmo motorista,
  mesma sessão, controle da entidade e ignição sem desligamento explícito.
  Efeitos seguintes e partículas aguardando carregamento são cancelados ao sair.
- CDN Fuel: `LeaveEngineRunning` está desativado; não foi alterado.
- Revisados também controle de torque do Small Resources, piloto automático do
  HUD, freios da garagem e tarefas de NPC do Carkeys. Não há evidência no log
  disponível que atribua o burnout a algum desses caminhos. Não foram alterados.

O teste não simula torque, rodas ou física. Os testes passaram, mas a eliminação
do burnout precisa ser confirmada no FiveM. O log local consultado não tinha
rastreamento de aceleração ativo.

Para capturar o problema sem editar configuração: dentro do veículo execute
`/pr_engine_trace`, pare e saia. Durante 30 segundos o F8 recebe linhas
`[pr_carkeys:trace]` com motorista, controle da entidade, motor, RPM, acelerador,
velocidade, burnout, freio de mão, congelamento e última escrita do PR Carkeys.
A captura é somente leitura; `lastPRK` não identifica ações de outros recursos.

Reiniciar `pr_carkeys` e `pr_mileage` para carregar as alterações.

## Transação da ignição e tecla Z

Revisão restrita ao PR Carkeys. A ação é capturada na tecla, usando o veículo
real do motorista. Entrada e saída não chamam partida. A persistência de saída
é suspensa antes de desligar; o desligamento é confirmado antes de devolver
qualquer item. Rotinas de NPC deixam de manter o motor quando não há NPC ao
volante. Uso de chave aguardando animação é cancelado por comando Z posterior.

Inserir e devolver a chave usam callbacks confirmados e uma fila por veículo
no servidor, inclusive para os eventos legados. Falha de inventário conserva
o registro da chave, não anuncia sucesso e permite tentar a devolução com Z
novamente sem dar partida. Inventário, bolsa, placa falsa, chave temporária,
expiração e devoluções concorrentes têm testes próprios:

```powershell
python tests/test_engine_flow.py
python tests/test_ignition_keys.py
```

O segundo arquivo executa o módulo completo `server/sv_vehicle.lua` em Lua 5.4
com inventário, banco e natives simulados. Continua sendo necessária a
validação da física dentro do FiveM; estes testes não demonstram ausência de
burnout no jogo.
