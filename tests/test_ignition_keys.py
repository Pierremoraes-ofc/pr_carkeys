from pathlib import Path
from lupa.lua54 import LuaRuntime
r=Path(__file__).resolve().parents[1]
fixture=r"""
callbacks={};events={};sent={};tasks={};now=0;driver=10;plate='ABC';state={};qty=1;added=0;removed=0;addOK=true;sqlDelay=0;sqlError=false;inBag=false;expired=false
Config={KeyTypes={carkey={}},Default={UseKeyAnim={DefaultDistance=10}},Sound={soundDefault='lock'},Bags={}}
ActiveInventory='ox_inventory'
PRCarkeys={ResolveKeyPlate=function(p) if p=='FAKE' then return 'ABC' end return p end,IsKeyExpired=function() return expired end,Cache={InvalidateKey=function() end}}
function Debug() end
function GetPlayerPed() return 10 end
function DoesEntityExist(v) return v~=0 end
function NetworkGetEntityFromNetworkId(id) return id==101 and 1 or 0 end
function GetPedInVehicleSeat() return driver end
function GetVehicleNumberPlateText() return plate end
function GetGameTimer() return now end
function RegisterNetEvent(n,f) events[n]=f end
function AddEventHandler(n,f) events[n]=f end
function TriggerClientEvent(n,src,...) sent[#sent+1]=n end
function exports() end
function Wait(ms) coroutine.yield(ms) end
function CreateThread(f) tasks[#tasks+1]={co=coroutine.create(f),due=now} end
function tick(ms)
 local finish=now+ms
 while now<=finish do
  for _,t in ipairs(tasks) do
   if t.due<=now and coroutine.status(t.co)~='dead' then
    local ok,delay=coroutine.resume(t.co);assert(ok,delay);t.due=now+math.max(1,delay or 0)
   end
  end
  now=now+1
 end
end
function ExecuteSQL(q)
 if sqlError then error('database unavailable') end
 if sqlDelay>0 then Wait(sqlDelay) end
 if q:find('FROM pr_carkeys') then return {{barcode='SERIAL',plate='ABC',citizenid='citizen'}} end
 return {}
end
local function slots(inv,item)
 if item=='carkey_bag' and inBag then return {{metadata={barcode='BAG'}}} end
 if item~='carkey' then return {} end
 if qty<1 or (inBag and inv~='pr_carkeys_bag_BAG') or (not inBag and inv~=1) then return {} end
 return {{slot=1,metadata={barcode='SERIAL',plate='ABC'}}}
end
local inventory={
 Search=function(inv,kind,item,meta) return slots(inv,item) end,
 GetSlotsWithItem=slots,
 RemoveItem=function() if qty<1 then return false end;qty=qty-1;removed=removed+1;return true end,
 AddItem=function(inv) if not addOK then return false end;qty=qty+1;added=added+1;lastInventory=inv;return true end,
 RegisterStash=function() end,
}
Bridge={framework={GetIdentifier=function() return 'citizen' end},inventory=inventory}
pr_lib={inventory=inventory,fivem={vehicleState={raw={set=function(v,k,x) state[k]=x end}}},callback={register=function(n,f) callbacks[n]=f end}}
function put() return callbacks['pr_carkeys:server:putIgnitionKey'](1,101,plate) end
function take() return callbacks['pr_carkeys:server:returnIgnitionKey'](1,101,plate) end
function count(n) local total=0;for _,v in ipairs(sent) do if v==n then total=total+1 end end;return total end
"""
cases={
 'key moves into ignition and back once':"assert(put().ok and qty==0);assert(take().ok and qty==1 and added==1 and not VehiclesWithKeyInside[101] and state.pr_carkeys_ignition==false)",
 'repeated insertion does not remove twice':"assert(put().ok);assert(put().ok and removed==1)",
 'repeated return does not duplicate key':"assert(put().ok);assert(take().ok);assert(take().ok and added==1)",
 'full inventory preserves key and permits retry':"assert(put().ok);addOK=false;assert(not take().ok);assert(VehiclesWithKeyInside[101] and state.pr_carkeys_keyInIgnition and qty==0 and count('pr_carkeys:client:keyReturnedToInventory')==0);addOK=true;assert(take().ok and qty==1)",
 'temporary ignition key is retained on inventory failure':"assert(put().ok);VehiclesWithKeyInside[101].isCarjack=true;addOK=false;assert(not take().ok and VehiclesWithKeyInside[101]);addOK=true;assert(take().ok and qty==1)",
 'leaving vehicle preserves ignition item':"assert(put().ok);driver=0;assert(not take().ok and VehiclesWithKeyInside[101] and qty==0);driver=10;assert(take().ok and qty==1)",
 'fake plate resolves original ignition key':"plate='FAKE';assert(put().ok and VehiclesWithKeyInside[101].plate=='ABC');assert(take().ok and qty==1)",
 'database failure preserves key and unlocks transaction':"assert(put().ok);sqlError=true;assert(not take().ok and VehiclesWithKeyInside[101]);sqlError=false;assert(take().ok and qty==1)",
 'concurrent return requests only add one item':"assert(put().ok);sqlDelay=100;CreateThread(function() result1=take() end);CreateThread(function() result2=take() end);tick(500);assert(result1.ok and result2.ok and added==1)",
 'bag receives original key':"inBag=true;assert(put().ok);CreateThread(function() result=take() end);tick(200);assert(result.ok and qty==1 and lastInventory=='pr_carkeys_bag_BAG')",
 'expired key is never returned':"assert(put().ok);expired=true;assert(take().ok and qty==0 and not VehiclesWithKeyInside[101] and not state.pr_carkeys_keyInIgnition)",
 'wrong vehicle identity cannot return key':"assert(put().ok);plate='OTHER';assert(not take().ok and added==0 and VehiclesWithKeyInside[101])",
}
for name,case in cases.items():
 lua=LuaRuntime();lua.execute(fixture);lua.execute((r/'server/sv_vehicle.lua').read_text(encoding='utf-8-sig'))
 try: lua.execute(case)
 except Exception: print('FAILED:',name);raise
 print('PASS:',name)
print(len(cases),'server ignition transaction scenarios passed (inventory and GTA mocked).')
