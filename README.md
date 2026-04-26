# 🔑 pr\_carkeys — Sistema de Chaves de Veículo

> **Versão:** 1.3.0 · **Autor:** Pierremoraes-ofc
> **Repositório:** [github.com/Pierremoraes-ofc/pr\_carkeys](https://github.com/Pierremoraes-ofc/pr_carkeys)

Sistema completo de chaves de veículos para FiveM com suporte a múltiplos frameworks, inventários e bancos de dados. Possui tipos de chave, bolsas, hotwire, carjack, minigames configuráveis, sons 3D, expiração automática e muito mais.

---

## 📋 Índice

* [Compatibilidade](#compatibilidade)
* [Instalação](#instalação)
* [Estrutura de Arquivos](#estrutura-de-arquivos)
* [Tipos de Chave](#tipos-de-chave)
* [Tipos de Bolsa](#tipos-de-bolsa)
* [Funcionamento das Chaves](#funcionamento-das-chaves)
* [Sistema de Hotwire](#sistema-de-hotwire)
* [Sistema de Carjack](#sistema-de-carjack)
* [Chave no Veículo](#chave-no-veículo)
* [Sistema Policial](#sistema-policial)
* [Minigames](#minigames)
* [Sons 3D](#sons-3d)
* [Banco de Dados](#banco-de-dados)
* [Cache Server-Side](#cache-server-side)
* [Expiração Automática](#expiração-automática)
* [Comandos](#comandos)
* [Exports Server-Side](#exports-server-side)
* [Exports Client-Side](#exports-client-side)
* [Eventos de Rede (NetEvents)](#eventos-de-rede-netevents)
* [Configuração (config.lua)](#configuração-conflua)
* [Itens para Instalação](#itens-para-instalação)
* [Debug](#debug)

---

## Compatibilidade

### Frameworks suportados (detecção automática ou forçada)
| Framework | Coluna Owner |
|-----------|-------------|
| `qbx-core` | `citizenid` |
| `ND_Core` | `citizenid` |
| `ox_core` | `charId` |
| `es_extended` | `identifier` |
| `qb-core` | `citizenid` |

### Inventários suportados
| Inventário | Status |
|------------|--------|
| `ox_inventory` | Principal (recomendado) |
| `qb-inventory` | Suportado (fallback) |

### Bancos de dados suportados
| SQL | Status |
|-----|--------|
| `oxmysql` | Suportado |
| `ghmattimysql` | Suportado |
| `mysql-async` | Suportado |

### Recursos opcionais
| Recurso | Função |
|---------|--------|
| `ox_lib` | Menus, progressbar, skillcheck |
| `pr_3dsound` | Som 3D ao trancar/destrancar |
| `glitch-minigame` | Minigame de hotwire/carjack |
| `mhacking` | Minigame alternativo |

---

## Instalação

### 1. Adicionar ao servidor
Coloque a pasta `pr_carkeys` no diretório `resources` e adicione ao `server.cfg`:

```
ensure pr_carkeys
```

### 2. Banco de dados
A tabela é criada **automaticamente** ao iniciar o resource. Caso prefira criar manualmente, execute o arquivo `install/pr_carkeys.sql`.

### 3. Itens no inventário

**ox\_inventory** — adicione ao `ox_inventory/data/items.lua` o conteúdo de `install/ox-items.lua`.

**qb-inventory** — adicione ao `qb-core/shared/items.lua` o conteúdo de `install/qb-items.lua`.

### 4. Sons (opcional)
Se usar `pr_3dsound`, copie os arquivos `.ogg` da pasta `song/` para:
```
pr_3dsound/html/sounds/pr_carkeys/
```

---

## Estrutura de Arquivos

```
pr_carkeys/
├── config/
│   └── config.lua              # Toda a configuração do sistema
├── shared/
│   ├── main.lua                # Detecção de framework/inventário/SQL, utilitários, funções globais
│   └── bridge.lua              # Bridge multi-framework (client e server)
├── server/
│   ├── sv_main.lua             # Inicialização, auto SQL, registro de itens usáveis, cleanup
│   ├── sv_cache.lua            # Cache server-side das chaves (barcode → dados do banco)
│   ├── sv_keys.lua             # CRUD das chaves + som 3D
│   ├── sv_vehicle.lua          # Lógica de veículos: lock, ignição, chave na ignição, carjack
│   ├── sv_bag.lua              # Gerenciamento de bolsas de chaves
│   ├── sv_commands.lua         # Comando /givekey + funções internas CreateTempKeyItem/CreateTimedKeyItem
│   ├── sv_shop.lua             # Exports de loja: BuyOriginalKey, CopyKey
│   └── sv_expiration.lua       # Loop de expiração de chaves single_use e temporary
├── client/
│   ├── cl_main.lua             # Inicialização client, utilitários (Notify, ProgressBar, FindVehicleByPlate)
│   ├── cl_keys.lua             # Uso da chave (trancar/destrancar/motor)
│   ├── cl_bag.lua              # Interface da bolsa de chaves
│   ├── cl_menu.lua             # Menus de gerenciamento de chaves (ox_lib / qb-menu)
│   └── modules/
│       ├── vehicle_state.lua   # Estado global do veículo e das chaves do jogador
│       ├── vehicle_lock.lua    # Lógica de travar/destrancar com verificação policial
│       ├── vehicle_init.lua    # Loop principal: entrada/saída de veículo, hotwire, chave na ignição
│       ├── key_in_vehicle.lua  # Detecção de chave deixada no carro
│       └── carjack.lua         # Sistema completo de carjack (roubo de NPC com arma)
├── install/
│   ├── pr_carkeys.sql          # SQL manual (alternativa ao auto-create)
│   ├── ox-items.lua            # Itens para ox_inventory
│   └── qb-items.lua            # Itens para qb-inventory
├── song/
│   ├── tranca_1.ogg            # Som padrão de tranca
│   └── tranca_2.ogg            # Som alternativo
└── fxmanifest.lua
```

---

## Tipos de Chave

O sistema possui 4 tipos de chave configurados em `Config.KeyTypes`:

| Item | Label | keyType | level | Comportamento |
|------|-------|---------|-------|---------------|
| `carkey_permanent` | Chave Original | `permanent` | `original` | Chave física persistente, nunca expira, registrada no banco |
| `carkey_copy` | Chave Cópia | `permanent` | `copy` | Igual à original, mas identificada como cópia |
| `carkey_temp` | Chave Temporária | `temporary` | `copy` | Removida do inventário ao desconectar e ao iniciar o resource |
| `carkey_single` | Chave Avulsa | `single_use` | `copy` | Expira por cronômetro (`expires_at`), removida automaticamente pelo loop de expiração |

### Diferenças entre tipos
- **`permanent`** — armazenada no banco de dados, persiste entre sessões, configurável (som, motor, distância).
- **`temporary`** — existe apenas como item físico no inventário; é limpa ao entrar/sair da cidade e ao reiniciar o resource. Não é registrada no banco.
- **`single_use`** — registrada no banco com `expires_at`. Após expirar, é removida automaticamente do inventário, bolsas e ignição, e o veículo é desligado.

---

## Tipos de Bolsa

Configurados em `Config.Bags`:

| Item | Label | Slots | Peso máx. | Tempo de abertura |
|------|-------|-------|-----------|------------------|
| `carkey_bag` | Bolsa de Chaves | 10 | 5.000g | 3s |
| `carkey_bag_large` | Bolsa de Chaves Grande | 25 | 15.000g | 4s |

As bolsas funcionam como **stashes do ox\_inventory** vinculados ao barcode do item. Ao usar a bolsa, o jogador pode:
- Abrir o stash diretamente no ox\_inventory
- Ou abrir o menu ox\_lib primeiro (conforme `Config.Default.KeyMetadata.openMenu`)

---

## Funcionamento das Chaves

### Ciclo de vida completo

```
1. CRIAÇÃO
   ├── /givekey → sv_commands.lua → AddItem ao inventário
   ├── BuyOriginalKey (export) → sv_shop.lua → INSERT banco + AddItem
   ├── CopyKey (export) → sv_shop.lua → INSERT banco + AddItem
   ├── GiveTempKey (export) → sv_vehicle.lua → AddTempKey (sem item físico)
   └── CreateTempKeyItem → sv_commands.lua → AddItem (sem banco, apenas item)

2. SINCRONIZAÇÃO CLIENT
   ├── Ao logar: VehicleState:RebuildFromInventory() lê itens do inventário
   ├── Barcode encontrado → TriggerServerEvent fetchKeyDbData → busca dados no banco
   └── Dados retornam → VehicleState:AddPermanentKey(plate, data)

3. USO (Tecla L por padrão)
   ├── VehicleLock:Toggle() detecta veículo próximo pela placa
   ├── TriggerServerEvent useKey(barcode, netId, coords)
   ├── Servidor valida expiração → toca som 3D via pr_3dsound
   └── TriggerClientEvent executeUseKey → client trava/destrava + animação

4. EXPIRAÇÃO
   ├── single_use: loop sv_expiration.lua a cada 5s verifica expires_at
   ├── Expirado: desliga veículo → remove do inventário/bolsas/ignição → DELETE banco
   └── temporary: removida ao playerDropped e playerLoaded

5. DELEÇÃO MANUAL
   └── TriggerServerEvent deleteKey(barcode) → DELETE banco + InvalidateKey cache
```

### Barcode (Serial)
Cada chave possui um **barcode único** no formato `6dígitos + 3letras + 6dígitos` (ex: `123456ABC789012`). O barcode é o identificador primário em todo o sistema: banco de dados, cache, metadata do item e eventos de rede.

### Metadata do item
Cada chave no inventário contém:
```lua
{
    label         = "Modelo: Adder\nPlaca: ABC1234\nProprietario: João Silva\nSerial: 123456ABC789012",
    barcode       = "123456ABC789012",
    plate         = "ABC1234",
    modelo        = "Adder",
    code          = "123456ABC789012",    -- alias de barcode
    proprietario  = "João Silva",         -- se Config.Default.KeyMetadata.showOwner = true
}
```

### Configurações individuais por chave
Cada chave no banco tem configurações editáveis via menu:
| Campo | Descrição | Padrão |
|-------|-----------|--------|
| `sound` | Som de tranca/destranca | `tranca_1` |
| `motor` | Liga motor ao destrancar | `false` |
| `distance` | Distância do sinal (metros) | `8.0` |

---

## Sistema de Hotwire

Permite ligar um veículo na força sem possuir a chave, através de um minigame.

**Tecla padrão:** `H` (configurável em `Config.Hotwire.hotwireKey`)

### Modos
| Modo | Quando aparece |
|------|---------------|
| `parked` | Veículo estacionado (sem motorista NPC) |
| `carjack` | Veículo com NPC motorista durante roubo |

### Fluxo
1. Player pressiona `H` próximo a um veículo sem chave
2. Minigame é iniciado (configurado em `Config.Minigame`)
3. **Sucesso:** `TriggerServerEvent grantTemporaryVehicleAccess` → servidor concede chave temporária lógica (`GiveTempKey`)
4. **Falha:** notificação de sem permissão

### Blacklist de veículos
Veículos listados em `Config.NoKeyNeeded` não requerem chave nem hotwire (bicicletas, etc.):
```lua
Config.NoKeyNeeded = {
    [`bmx`] = true, [`cruiser`] = true, [`fixter`] = true, ...
}
```

---

## Sistema de Carjack

Sistema completo de roubo de veículo de NPC com arma.

**Ativação:** Aponte uma arma válida para um NPC motorista e pressione `E`

### Fluxo do carjack
```
1. Player mira arma → NPC detectado dentro de Config.Carjack.aimDistance (30m)
2. Hint "[E] Procurar chave" aparece
3. Player pressiona E → NPC vai de mãos ao alto (handsUp)
4. Rolar chance de reação do NPC:
   ├── NPC reage (chance por classe de arma): saca arma ou foge com carro
   └── NPC obedece: progress bar "Ligando veículo..." (5–7s configurável)
5. Minigame de carjack (vehiCarjack — mais difícil que parked)
6. Sucesso:
   ├── Config.Carjack.getPermKey = true  → chave permanente (item no banco)
   └── Config.Carjack.getPermKey = false → chave temporária lógica (GiveTempKey)
7. NPC é removido, veículo liberado
```

### Armas bloqueadas para carjack
Armas brancas, explosivas e sem dano não podem iniciar carjack (lista em `Config.Carjack.blacklistedWeapons`).

### Chance de reação por classe de arma
```lua
handguns  = 50%   fuga
SMG       = 75%   fuga
shotgun   = 90%   fuga
assault   = 90%   fuga
LMG       = 99%   fuga
sniper    = 99%   fuga
heavy     = 99%   fuga
melee     = 0%    sem reação
```

### Sistema policial no carjack
Policiais (jobs em `Config.Police.jobs`) veem o hint `[E] Confiscar veículo`. Ao pressionar:
- Progress bar "Confiscando veículo..."
- Veículo é travado, NPC rendido é removido
- Policial ganha acesso sem chave

---

## Chave no Veículo

Controlado por `Config.KeyInVehicle`.

### Funcionamento
1. Jogador entra no veículo como motorista
2. Sistema verifica se há chave no inventário para aquela placa
3. **Sem chave:** verifica se há chave deixada no carro (outro jogador deixou)
   - Se encontrar: hint "Pegando chave do carro..." com progress bar (2s)
   - Player pode pegar a chave para si
4. **Motor ligado ao sair do veículo:**
   - Se `keepVehicleEngineOn = true`: motor permanece ligado
   - A chave "fica" no veículo (`keyLeftInVehicle` registrado no servidor)
   - Outro player pode entrar e pegar a chave
5. **Ao desligar o motor:** chave retorna ao inventário automaticamente

### Eventos relacionados
| Evento | Direção | Descrição |
|--------|---------|-----------|
| `pr_carkeys:server:keyLeftInVehicle` | C→S | Registra chave deixada no veículo |
| `pr_carkeys:server:returnKeyFromVehicle` | C→S | Chave retorna ao inventário |
| `pr_carkeys:server:checkKeyInVehicle` | C→S | Verifica se há chave no carro |
| `pr_carkeys:server:pickupKeyFromVehicle` | C→S | Player pega a chave do carro |
| `pr_carkeys:client:keyAvailableInVehicle` | S→C | Notifica que há chave disponível |
| `pr_carkeys:client:keyPickedUp` | S→C | Confirma que a chave foi pega |
| `pr_carkeys:client:keyTakenFromVehicle` | S→C | Chave foi pega por outro player |
| `pr_carkeys:client:keyReturnedToInventory` | S→C | Chave devolvida ao inventário |

---

## Sistema Policial

Configurado em `Config.Police`.

```lua
Config.Police = {
    enabled = true,
    jobs    = { "police", "sheriff", "swat" },
}
```

### Permissões especiais
- **Trancar/destrancar qualquer veículo** sem possuir a chave
- **Confiscar veículo de NPC** durante carjack (pressionar `E` enquanto NPC está rendido)
- Acesso via `VehicleLock:IsPolice()` que verifica o job atual do player no framework detectado

---

## Minigames

Configurado em `Config.Minigame`. Suporta 3 sistemas:

| Sistema | Config |
|---------|--------|
| `ox_lib` | skillcheck nativo do ox_lib |
| `glitch-minigame` | Resource externo com múltiplos minigames |
| `mhacking` | Resource externo alternativo |

### Minigames disponíveis no glitch-minigame
`BruteForce`, `HoldZone`, `SkillCheck`, `NumberUp`, `ComboInput`, `WireConnect`, `SimonSays`, `AimTest`, `CircleClick`, `Lockpick`, `Keymash`, `Untangle`, `Pairs`, `MemoryColors`, `Fingerprint`, `CodeCrack`, `FirewallPulse`, `BackdoorSequence`, `Rhythm`, `Memory`, `SequenceMemory`, `VerbalMemory`, `NumberedSequence`, `SymbolSearch`, `VarHack`, `WordCrack`, `Balance`, `DataCrack`, `CircuitBreaker`, `PlasmaDrilling`

### Dois níveis de dificuldade
| Modo | Contexto |
|------|---------|
| `vehiParked` | Hotwire em veículo estacionado (mais fácil) |
| `vehiCarjack` | Hotwire durante carjack com NPC (mais difícil) |

---

## Sons 3D

Integração com `pr_3dsound` para sons audíveis por todos os players no raio.

```lua
Config.Sound = {
    radius       = 8.0,
    volume       = 0.8,
    soundDefault = 'tranca_1',
    sounds = {
        { id = 'tranca_1', label = 'Som Padrão',      file = 'tranca_1.ogg' },
        { id = 'tranca_2', label = 'Som Alternativo', file = 'tranca_2.ogg' },
    },
}
```

Cada jogador pode escolher o som da sua chave individualmente pelo menu de gerenciamento. O som é salvo no banco de dados por chave (`sound` field).

---

## Banco de Dados

### Tabela `pr_carkeys`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | INT AUTO\_INCREMENT | Chave primária |
| `barcode` | VARCHAR(20) UNIQUE | Serial único da chave |
| `citizenid` | VARCHAR(50) | Dono da chave |
| `plate` | VARCHAR(15) | Placa do veículo |
| `key_type` | VARCHAR(20) | `permanent` \| `temporary` \| `single_use` |
| `sound` | VARCHAR(50) | ID do som configurado |
| `motor` | TINYINT(1) | 1 = liga motor ao destrancar |
| `level` | VARCHAR(20) | `original` \| `copy` |
| `distance` | FLOAT | Distância do sinal (metros) |
| `expires_at` | BIGINT NULL | Timestamp UNIX de expiração |
| `created_at` | TIMESTAMP | Data de criação |

**Índices:** `idx_barcode`, `idx_citizenid`, `idx_plate`

### Wrapper SQL universal
O arquivo `shared/main.lua` expõe duas funções globais (apenas server-side):

```lua
-- SELECT: retorna array de rows
ExecuteSQL(query, parameters)

-- INSERT: retorna o ID gerado
ExecuteSQLInsert(query, parameters)
```

Suporta `oxmysql`, `ghmattimysql` e `mysql-async` automaticamente.

---

## Cache Server-Side

`sv_cache.lua` mantém um cache em memória das chaves para evitar queries repetitivas ao banco.

| Função | Descrição |
|--------|-----------|
| `PRCarkeys.Cache.GetKey(barcode)` | Retorna dados (cache first, depois banco) |
| `PRCarkeys.Cache.SetKey(barcode, data)` | Popula cache após INSERT |
| `PRCarkeys.Cache.InvalidateKey(barcode)` | Remove do cache após DELETE |
| `PRCarkeys.Cache.UpdateField(barcode, field, value)` | Atualiza campo sem invalidar |

O cache possui índice secundário `citizenid → barcodes[]` para limpeza eficiente O(1) ao desconectar.

---

## Expiração Automática

`sv_expiration.lua` executa um loop a cada **5 segundos** verificando chaves expiradas:

### Ordem de operações ao expirar
1. Verifica se a chave está na ignição de algum veículo
2. Delega desligamento ao client do motorista (`forceEngineOff`)
3. Remove da ignição (registro `VehiclesWithKeyInside`)
4. Remove do inventário/bolsas do motorista
5. Fallback: varre todos os players online e remove onde existir
6. DELETE do banco + InvalidateKey do cache

### Chaves temporárias (`keyType = "temporary"`)
São limpas em 3 momentos (sem usar o loop de expiração):
- Ao iniciar o resource (`onResourceStart`)
- Ao jogador entrar (`playerLoaded` / `QBCore:Server:OnPlayerLoaded`)
- Ao jogador sair (`playerDropped`)

---

## Comandos

### `/givekey`
Dá uma chave para um jogador. Apenas admins (ace `command.givekey`) ou console.

```
/givekey [id] [tipo] [placa] [duração_segundos]
```

**Aliases de tipo:**

| Tipo | Aliases |
|------|---------|
| Chave Original | `permanente`, `permanent` |
| Chave Cópia | `copia`, `copy` |
| Chave Temporária | `temporaria`, `temp`, `temporary` |
| Chave Avulsa (timer) | `unico`, `single`, `single_use` |

**Exemplos:**
```
/givekey 1 permanente ABC1234
/givekey 1 permanent ABC1234
/givekey 1 copia ABC1234
/givekey 1 temporaria ABC1234
/givekey 1 unico ABC1234 120          ← expira em 120 segundos
/givekey 1 single_use ABC1234 600     ← expira em 600 segundos (padrão)
```

---

## Exports Server-Side

Todos os exports são chamados de outros resources via `exports["pr_carkeys"]:NomeFuncao(...)`.

---

### `BuyOriginalKey(src, plate, duration?)`
Cria e entrega uma chave original para o jogador. Insere no banco de dados.

```lua
local result = exports["pr_carkeys"]:BuyOriginalKey(source, "ABC1234")
-- result = { success = true, barcode = "123456ABC789012" }

-- Com expiração (segundos):
local result = exports["pr_carkeys"]:BuyOriginalKey(source, "ABC1234", 3600)
```

**Retorno:**
```lua
{ success = true,  barcode = "..." }
{ success = false, reason  = "player_not_found" | "invalid_plate" | "db_error" | "item_not_found" }
```

---

### `CopyKey(src, originalBarcode, duration?)`
Cria uma cópia de uma chave existente. Não copia chaves `single_use`.

```lua
local result = exports["pr_carkeys"]:CopyKey(source, "123456ABC789012")
-- result = { success = true, barcode = "654321XYZ098765" }
```

**Retorno:**
```lua
{ success = true,  barcode = "..." }
{ success = false, reason  = "player_not_found" | "original_not_found" | "cannot_copy_single_use" | "db_error" }
```

---

### `GiveTempKey(src, plate)`
Concede acesso temporário **lógico** ao veículo (sem item físico no inventário, sem banco de dados). Usado por hotwire e carjack internamente.

```lua
exports["pr_carkeys"]:GiveTempKey(source, "ABC1234")
```

---

### `RemoveTempKey(src, plate)`
Remove o acesso temporário lógico de um jogador a uma placa.

```lua
exports["pr_carkeys"]:RemoveTempKey(source, "ABC1234")
```

---

### `GiveKeys(src, vehicle)`
Concede chaves de um veículo para o jogador. Detecta automaticamente qb-vehiclekeys ou ND\_vehicleKeys.

```lua
exports["pr_carkeys"]:GiveKeys(source, vehicleEntity)
```

---

### `IsPlayerPolice(src)`
Verifica se o jogador está em um job policial configurado em `Config.Police.jobs`.

```lua
local isPolice = exports["pr_carkeys"]:IsPlayerPolice(source)
-- retorna: true | false
```

---

### `SetLockState(vehicle, state)`
Define o estado de tranca de um veículo pelo entity.

```lua
exports["pr_carkeys"]:SetLockState(vehicleEntity, 1)  -- 1 = travado, 2 = destravado
```

---

## Exports Client-Side

> **Nota:** O sistema não expõe exports client-side diretos via `exports(...)`. A comunicação client↔server é feita exclusivamente via NetEvents e eventos registrados no Bridge.

As funções internas do client utilizáveis internamente por outros módulos do resource:

| Função | Descrição |
|--------|-----------|
| `PRCarkeys.Notify(data)` | Envia notificação via Bridge |
| `PRCarkeys.ProgressBar(label, duration, anim, cb)` | Exibe barra de progresso com animação |
| `PRCarkeys.FindVehicleByPlate(plate, maxDistance)` | Encontra veículo próximo pela placa |
| `PRCarkeys.IsVehicleBlacklisted(vehicle)` | Verifica se veículo está na blacklist |
| `VehicleState:HasKey(plate)` | Verifica se player tem chave para a placa |
| `VehicleState:GetKeyData(plate)` | Retorna dados da chave permanente |
| `VehicleState:AddTempKey(plate)` | Adiciona chave temporária local |
| `VehicleState:RemoveTempKey(plate)` | Remove chave temporária local |
| `VehicleState:AddPermanentKey(plate, data)` | Adiciona/atualiza chave permanente |
| `VehicleState:RebuildFromInventory()` | Reconstrói estado a partir do inventário |

---

## Eventos de Rede (NetEvents)

### Client → Server

| Evento | Parâmetros | Descrição |
|--------|-----------|-----------|
| `pr_carkeys:server:createKey` | `data` (barcode, plate, key\_type, ...) | Cria chave no banco |
| `pr_carkeys:server:useKey` | `barcode, netId, vehicleCoords` | Usa chave (valida + som) |
| `pr_carkeys:server:updateKeyConfig` | `barcode, field, value` | Atualiza sound/motor/distance |
| `pr_carkeys:server:getKeyData` | `barcode` | Busca dados da chave no cache/banco |
| `pr_carkeys:server:deleteKey` | `barcode` | Deleta chave do banco |
| `pr_carkeys:server:setVehicleLockState` | `vehNetId, state, plate` | Define estado de tranca no servidor |
| `pr_carkeys:server:validateDriverSeat` | `vehNetId, plate` | Valida se player pode sentar como motorista |
| `pr_carkeys:server:keyLeftInVehicle` | `vehNetId, plate` | Registra chave deixada no veículo |
| `pr_carkeys:server:returnKeyFromVehicle` | `vehNetId, plate` | Chave retorna ao inventário |
| `pr_carkeys:server:checkKeyInVehicle` | `vehNetId, plate` | Verifica chave disponível no veículo |
| `pr_carkeys:server:pickupKeyFromVehicle` | `vehNetId, plate, barcode?` | Player pega chave do veículo |
| `pr_carkeys:server:fetchKeyDbData` | `plate, barcode` | Busca dados do banco para sincronização |
| `pr_carkeys:server:fetchAllKeyDbData` | `barcodes[]` | Busca dados em lote |
| `pr_carkeys:server:syncTempKeys` | — | Sincroniza chaves temporárias ao logar |
| `pr_carkeys:server:playLockSound` | `coords, soundId` | Toca som de tranca via pr\_3dsound |
| `pr_carkeys:server:grantTemporaryVehicleAccess` | `vehNetId, plate` | Concede acesso temp (hotwire) |
| `pr_carkeys:server:grantTemporaryKeyItemNearbyVehicle` | `vehNetId, plate` | Concede item de chave temp por proximidade |
| `pr_carkeys:server:manageBag` | `slot` | Gerencia bolsa de chaves |
| `pr_carkeys:server:openBag` | `slot` | Abre bolsa de chaves |
| `pr_carkeys:server:manageKey` | `slot` | Gerencia chave por slot |
| `pr_carkeys:server:manageKeyByBarcode` | `barcode` | Gerencia chave por barcode |
| `pr_carkeys:server:carjackRegisterKey` | `plate, vehNetId` | Registra chave obtida por carjack |
| `pr_carkeys:server:carjackSuccess` | `plate` | Notifica sucesso do carjack |

### Server → Client

| Evento | Parâmetros | Descrição |
|--------|-----------|-----------|
| `pr_carkeys:client:useBag` | `data` (slot, item) | Aciona uso da bolsa |
| `pr_carkeys:client:useKey` | `data` (slot, item) | Aciona uso da chave |
| `pr_carkeys:client:executeUseKey` | `keyData` | Executa travar/destrancar com dados validados |
| `pr_carkeys:client:keyCreated` | `{ success, barcode }` | Confirmação de criação de chave |
| `pr_carkeys:client:keyExpired` | — | Chave expirada |
| `pr_carkeys:client:keyConfigUpdated` | `barcode, field, value` | Confirmação de atualização de config |
| `pr_carkeys:client:getKeyDataReturn` | `row` | Retorno de dados da chave |
| `pr_carkeys:client:openManageMenu` | `menuData` | Abre menu de gerenciamento de chave |
| `pr_carkeys:client:openKeySubMenu` | `args` | Abre submenu de chave |
| `pr_carkeys:client:openStash` | `stashId` | Abre stash da bolsa |
| `pr_carkeys:client:driverSeatValidation` | `result` | Resultado da validação de assento |
| `pr_carkeys:client:clearDriverHintUI` | — | Limpa hint da interface |
| `pr_carkeys:client:keyAvailableInVehicle` | `plate, barcode` | Há chave disponível no veículo |
| `pr_carkeys:client:keyPickedUp` | `plate` | Chave pega com sucesso |
| `pr_carkeys:client:addTempKey` | `plate` | Adiciona chave temporária ao estado local |
| `pr_carkeys:client:removeTempKey` | `plate` | Remove chave temporária do estado local |
| `pr_carkeys:client:keyTakenFromVehicle` | `plate` | Chave foi pega por outro player |
| `pr_carkeys:client:keyReturnedToInventory` | `plate` | Chave devolvida ao inventário |
| `pr_carkeys:client:allKeyDbData` | `rows[]` | Dados em lote do banco |
| `pr_carkeys:client:keyDbData` | `data` | Dados de uma chave do banco |
| `pr_carkeys:client:forceInventoryRebuild` | — | Força reconstrução do inventário local |
| `pr_carkeys:client:forceEngineOff` | `vehNetId` | Desliga motor remotamente |
| `pr_carkeys:client:carjackLootKeyResult` | `success, data` | Resultado do loot de chave por carjack |
| `pr_carkeys:client:grantTempAccessResult` | `success, data` | Resultado de concessão de acesso temporário |

---

## Configuração (config.lua)

### Configurações principais

```lua
Config.Debug     = true             -- Habilita logs coloridos no console
Config.SQL       = "auto"           -- "auto" | "oxmysql" | "ghmattimysql" | "mysql-async"
Config.Framework = "auto"           -- "auto" | "qb-core" | "qbx-core" | "es_extended" | "ox_core" | "ND_Core"
Config.Inventory = "auto"           -- "auto" | "ox_inventory" | "qb-inventory"
```

### Config.Default
```lua
Config.Default = {
    closeInventory  = false,         -- Fecha ox_inventory ao abrir menu
    LockKey         = 'L',           -- Tecla de trancar/destrancar
    EngineKey       = 'Z',           -- Tecla de ligar/desligar motor

    KeyMetadata = {
        showOwner = true,            -- Mostra proprietário no metadata da chave
        openMenu  = false,           -- true = abre menu ox_lib | false = abre stash direto
    },

    UseKeyAnim = {
        dict     = "anim@mp_player_intmenu@key_fob@",
        clip     = "fob_click",
        flag     = 49,
        waitTime = 500,              -- Duração da animação (ms)
        DefaultDistance = 8.0,       -- Distância padrão do sinal (metros)
    }
}
```

### Config.Hotwire
```lua
Config.Hotwire = {
    enabled       = true,
    hintText      = "[H] Ligação direta",
    hotwireKey    = "H",
    minigameMode  = "parked",        -- "parked" | "carjack"
    notifySuccess = nil,             -- nil = mensagem padrão
    notifyFail    = nil,
}
```

### Config.Carjack
```lua
Config.Carjack = {
    enabled        = true,
    minTime        = { 5000, 7000 }, -- Tempo de roubo (ms)
    cooldown       = { 5000, 10000 },
    getPermKey     = false,          -- true = chave permanente | false = temporária
    hintText       = "[E] Procurar chave",
    aimDistance    = 30.0,
    npcReactChance = 0.30,           -- Chance do NPC puxar arma (0.0–1.0)
}
```

### Config.Police
```lua
Config.Police = {
    enabled = true,
    jobs    = { "police", "sheriff", "swat" },
}
```

### Config.KeyInVehicle
```lua
Config.KeyInVehicle = {
    enabled             = true,
    keepVehicleEngineOn = true,      -- Motor permanece ligado ao sair
    pickupTime          = 2000,      -- Tempo para pegar a chave (ms)
    pickupLabel         = "Pegando chave do carro...",
}
```

---

## Itens para Instalação

### ox\_inventory (`install/ox-items.lua`)
Registra os itens com callbacks para gerenciamento:
- `carkey_bag` — abre stash ou menu
- `carkey_bag_large` — abre stash ou menu
- `carkey_permanent` — abre menu de gerenciamento
- `carkey_copy` — abre menu de gerenciamento
- `carkey_temp` — abre menu de gerenciamento
- `carkey_single` — abre menu de gerenciamento

### qb-inventory (`install/qb-items.lua`)
Registra os mesmos itens com callbacks compatíveis com QBCore.

---

## Debug

O sistema possui logs coloridos no console quando `Config.Debug = true`:

| Nível | Cor | Uso |
|-------|-----|-----|
| `SUCCESS` | Verde | Operações bem-sucedidas |
| `INFO` | Amarelo | Informações gerais |
| `WARNING` | Azul | Avisos não-críticos |
| `ERROR` | Vermelho | Erros que precisam atenção |

**Exemplo de uso:**
```lua
Debug("SUCCESS", "Chave criada com sucesso | barcode=" .. barcode)
Debug("ERROR", "Falha ao inserir no banco | plate=" .. plate)
```

---

## Informações Adicionais

### Eventos de compatibilidade
O sistema escuta eventos de outros resources para compatibilidade:
- `qb-vehiclekeys:server:setVehLockState` — compatibilidade com qb-vehiclekeys
- `qb-vehiclekeys:server:AcquireVehicleKeys` — compatibilidade com qb-vehiclekeys
- `mm_carkeys:server:acquiretempvehiclekeys` — compatibilidade com mm\_carkeys

### Gerador de Barcode
```lua
-- Formato: 6dígitos + 3letras + 6dígitos
-- Exemplo: 847291XKZ039281
PRCarkeys.GenerateBarcode(text?)
```

### Funções utilitárias globais
| Função | Descrição |
|--------|-----------|
| `PRCarkeys.SanitizePlate(plate)` | Remove espaços e converte para maiúsculo |
| `PRCarkeys.GetStashId(bagBarcode)` | Retorna o stashId da bolsa |
| `PRCarkeys.ResolveKeyItem(keyType, level)` | Resolve o itemName pelo tipo e nível |
| `PRCarkeys.IsBag(itemName)` | Verifica se o item é uma bolsa |
| `PRCarkeys.IsKey(itemName)` | Verifica se o item é uma chave |
| `PRCarkeys.IsVehicleBlacklisted(vehicle)` | Verifica blacklist |
| `PRCarkeys.ResolveSoundFile(soundId)` | Retorna arquivo de som pelo ID |
| `PRCarkeys.IsKeyExpired(row)` | Verifica se uma chave está expirada |


Permanente (original):              /givekey 1 permanente 27DML069 ou /givekey 1 permanent 27DML069
Permanente (cópia):                 /givekey 1 copia 27DML069 ou /givekey 1 copy 27DML069
Temporária (carkey_temp):           /givekey 1 temporaria 27DML069 ou /givekey 1 temporary 27DML069
Uso único com cronômetro:           /givekey 1 unico 27DML069 120
Uso único com cronômetro:           /givekey 1 single_use 27DML069 120
Uso único com cronômetro:           /givekey 1 single 27DML069 120
Uso único com cronômetro (duração): /givekey 1 unico 27DML069 (default 600s)