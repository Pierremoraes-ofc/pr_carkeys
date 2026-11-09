from pathlib import Path
import re
from lupa.lua54 import LuaRuntime
r=Path(__file__).resolve().parents[1]
fixture=r'''
now=0; running=false; driver=10; owner=true; exists=true; startDelay=100; startAt=nil; callbackDelay=0; allowed=true; neverStart=false;returnOK=true;putOK=true;flagAtStop=nil;keepAbandoned=false;relightOnReturn=false;exitPreserved=false
pedFlags={};flagCalls={};keepCalls={};calls={}; sent={}; notifications={}; logs={}; events={}; cacheCallbacks={}; commands={}; tasks={}; state={fuel=50}
function state:set(k,v) self[k]=v end
Config={Debug=true,Default={EngineKey='Z',LockKey='L',RevEngineEffect=false},Notify={noPermission='denied'},KeyInVehicle={enabled=true,keepVehicleEngineOn=true},Hotwire={enabled=true},KeyTypes={},Sound={}}
cache={ped=10,vehicle=1,seat=-1}; ActiveInventory='ox_inventory'
PRCarkeys={SanitizePlate=function(p) return p end,GetVehicleKeyPlate=function(v) return 'ABC' end,Notify=function(n) notifications[#notifications+1]=n end,KeyInVehicle={},IsVehicleBlacklisted=function() return false end}
VehicleState={currentVehicle=1,currentPlate='ABC',hasKey=true,permanentKeys={},temporaryKeys={},GetKeyData=function() return {} end,HasKey=function() return true end,RebuildFromInventory=function() end,RemoveTempKey=function() end,RemovePermanentKey=function() end}
PRCarkeys.VehicleState=VehicleState
function Debug(level,msg) logs[#logs+1]=msg end
function CreateThread(f) tasks[#tasks+1]={co=coroutine.create(f),due=now} end
function Wait(ms) coroutine.yield(ms) end
function tick(ms)
 local finish=now+ms
 while now<=finish do
  for _,t in ipairs(tasks) do
   if t.due<=now and coroutine.status(t.co)~='dead' then
    local ok,delay=coroutine.resume(t.co); assert(ok,delay); t.due=now+math.max(1,delay or 0)
   end
  end
  now=now+1
 end
end
function RegisterNetEvent(n,f) events[n]=f end
function AddEventHandler(n,f) events[n]=f end
function RegisterCommand(n,f) commands[n]=f end
function RegisterKeyMapping() end
function TriggerServerEvent(n,...) sent[#sent+1]={name=n,args={...}} end
function GetGameTimer() return now end
function PlayerPedId() return 10 end
function GetPedConfigFlag(p,f) return pedFlags[f] == true end
function SetPedConfigFlag(p,f,v) assert(f==241 or f==429);pedFlags[f]=v;flagCalls[#flagCalls+1]={flag=f,value=v} end
function SetVehicleKeepEngineOnWhenAbandoned(v,on) keepAbandoned=on;keepCalls[#keepCalls+1]=on end
function GetCurrentResourceName() return 'pr_carkeys' end
function exitVehicle()
 local wasRunning=running
 exitPreserved=false
 driver=0;cache.vehicle=false;cache.seat=false;VehicleState.currentVehicle=0
 if cacheCallbacks.vehicle then cacheCallbacks.vehicle(false,1) end
 if wasRunning and not exitPreserved then running=false end
end
function DoesEntityExist(v) return exists end
function GetPedInVehicleSeat(v,s) return driver end
function GetVehiclePedIsIn() return cache.vehicle or 0 end
function NetworkHasControlOfEntity() return owner end
function NetworkRequestControlOfEntity() end
function NetworkGetNetworkIdFromEntity() return 101 end
function NetworkDoesNetworkIdExist() return exists end
function NetToVeh() return 1 end
function Entity(v) return {state=state} end
function GetIsVehicleEngineRunning(v)
 if startAt and now>=startAt then running=true;startAt=nil end
 return running
end
function SetVehicleEngineOn(v,on,instant,auto)
 calls[#calls+1]={on=on,time=now,instant=instant,auto=auto}
 if on then
  if driver==0 and instant==false then exitPreserved=true;running=true;startAt=nil
  elseif not neverStart then startAt=now+startDelay end
 else flagAtStop=pedFlags[429];running=false;startAt=nil end
end
function pressW() if not pedFlags[429] and not running then running=true end end
function GetVehicleFuelLevel() return 50 end
function GetVehicleEngineHealth() return 1000 end
function IsVehicleDriveable() return true end
function IsEntityDead() return false end
function GetGamePool() return {1} end
function DisableControlAction() end
function countEvent(n) local count=0;for _,e in ipairs(sent) do if e.name==n then count=count+1 end end;return count end
lib={onCache=function(n,f) cacheCallbacks[n]=f end,hideTextUI=function() end,showTextUI=function() end}
pr_lib={fivem={vehicleState={raw={watchAny=function() end,get=function(v,k) return state[k] end,set=function(v,k,x) state[k]=x end}}},framework={},callback={await=function(name)
 local answer=allowed
 if callbackDelay>0 then Wait(callbackDelay) end
 if name=='pr_carkeys:server:putIgnitionKey' then
  sent[#sent+1]={name='pr_carkeys:server:keyLeftInVehicle'}
  return {ok=putOK,reason='key_not_removed'}
 elseif name=='pr_carkeys:server:returnIgnitionKey' then
 sent[#sent+1]={name='pr_carkeys:server:returnKeyFromVehicle'}
  if relightOnReturn then running=true;startAt=nil end
  return {ok=returnOK,reason='inventory_full'}
 end
 return answer
end}}
Bridge={framework={isPolice=function() return false end}}
function TriggerEvent() end
PRCarkeys.Debug=function() end
VehicleState.UpdateKeyDbData=function() end
Config.Default.UseKeyAnim={dict='test',clip='key',time=100,flag=1,DefaultDistance=10}
function RequestAnimDict() end
function HasAnimDictLoaded() return true end
function TaskPlayAnim() end
function ClearPedTasks() end
function GetEntityModel() return 1 end
function PlayerId() return 1 end
function GetResourceState() return 'stopped' end
function GetVehicleDoorLockStatus() return state.doorslockstate or 2 end
function SetVehicleDoorsLocked() end
function SetVehicleDoorsLockedForAllPlayers() end
function SetVehicleDoorsLockedForPlayer() end
function SetVehicleUndriveable() end
function SetVehicleLights() end
function press() CreateThread(commands.pr_carkeys_ignition) end
function unlock() VehicleState.GetKeyData=function() return {motor=true} end;CreateThread(function() PRCarkeys.VehicleLock:Toggle() end) end
function seatReply(access,revision,id)
 events['pr_carkeys:client:driverSeatValidation']({plate='ABC',netId=101,requestId=id or 1,revision=revision or 0,hasAccess=access})
end
'''
files=['client/modules/engine_control.lua','client/modules/vehicle_lock.lua','client/modules/ignition_engine.lua','client/modules/vehicle_init.lua','client/cl_keys.lua']
cases={
'reentry adopts already running engine without a new start':"running=true;state.pr_carkeys_ignition=true;cacheCallbacks.vehicle(1);assert(pedFlags[429] and #calls==0);exitVehicle();assert(running and exitPreserved and #calls==1 and calls[1].on and calls[1].instant==false and calls[1].auto==true);driver=10;cache.vehicle=1;cache.seat=-1;VehicleState.currentVehicle=1;cacheCallbacks.vehicle(1,false);assert(running and #calls==1 and pedFlags[429])",
'old inventory key animation cannot undo Z stop':"running=true;CreateThread(function() events['pr_carkeys:client:executeUseKey']({plate='ABC',netId=101,motor=true}) end);tick(10);press();tick(500);assert(not running);for _,c in ipairs(calls) do assert(not c.on) end",
'stop blocks automatic start before engine write':"running=true;state.pr_carkeys_ignition=true;cacheCallbacks.vehicle(1);assert(pedFlags[429]);press();tick(500);assert(not running and flagAtStop==true and countEvent('pr_carkeys:server:returnKeyFromVehicle')==1)",
'stop does not require inventory key authorization':"running=true;tick(1);allowed=false;press();tick(500);assert(not running,'engine running');assert(countEvent('pr_carkeys:server:returnKeyFromVehicle')==1,'return count '..countEvent('pr_carkeys:server:returnKeyFromVehicle'))",
'full inventory keeps stopped engine and allows return retry':"running=true;returnOK=false;press();tick(100);assert(not running and PRCarkeys.pendingKeyReturnVehicle==1);returnOK=true;press();tick(500);assert(not running and PRCarkeys.pendingKeyReturnVehicle==nil and countEvent('pr_carkeys:server:returnKeyFromVehicle')==2);for _,c in ipairs(calls) do assert(not c.on) end",
'failed key insertion stops engine':"putOK=false;press();tick(300);assert(not running and not calls[#calls].on)",

'read-only trace never writes engine state':"print=function() end;running=true;commands.pr_engine_trace();tick(10);exitVehicle();tick(31000);assert(#calls==0)",
'expiry while awaiting authorization cancels request':"callbackDelay=100;press();tick(10);events['pr_carkeys:client:forceEngineOff'](101);tick(400);assert(not running and #calls==1 and not calls[1].on)",
'key taken while awaiting authorization cancels request':"callbackDelay=100;press();tick(10);events['pr_carkeys:client:keyTakenFromVehicle']('ABC');tick(400);assert(not running and #calls==1 and not calls[1].on)",
'new unlock works after previous explicit stop':"state.pr_carkeys_ignition=false;unlock();tick(600);assert(running and countEvent('pr_carkeys:server:keyLeftInVehicle')==1)",
'manual command supersedes pending remote entry':"running=true;unlock();tick(10);press();tick(600);assert(not running);for _,c in ipairs(calls) do assert(not c.on) end",
'remote lock shutdown is not undone by persistence':"running=true;state.pr_carkeys_ignition=true;state.doorslockstate=1;unlock();tick(10);driver=0;cache.seat=false;cache.vehicle=false;VehicleState.currentVehicle=0;tick(1500);assert(not running and #calls==1 and state.pr_carkeys_ignition==false)",

'delayed native start registers key':"press();tick(50);assert(countEvent('pr_carkeys:server:keyLeftInVehicle')==0);tick(200);assert(countEvent('pr_carkeys:server:keyLeftInVehicle')==1 and running)",
'key in ignition with engine off starts instead of stopping':"state.pr_carkeys_keyInIgnition=true;press();tick(300);assert(running and calls[1].on)",
'start timeout releases transition':"neverStart=true;press();tick(3200);assert(PRCarkeys.engineTransitionVehicle==nil and countEvent('pr_carkeys:server:keyLeftInVehicle')==0);neverStart=false;press();tick(200);assert(running)",
'duplicate key presses during callback':"callbackDelay=100;press();press();tick(400);assert(#calls==1 and running)",
'late denied seat response cannot stop approved start':"cacheCallbacks.seat(-1);press();tick(10);seatReply(false,0);tick(200);assert(running and #calls==1)",
'late watchdog denial superseded by new authorization':"running=true;allowed=false;callbackDelay=100;tick(0);running=false;allowed=true;press();tick(400);assert(running);for _,c in ipairs(calls) do assert(c.on) end",
'authorized seat entry keeps engine running':"running=true;cacheCallbacks.seat(-1);seatReply(true,0);assert(#calls==0 and running)",
'unauthorized start still blocked':"running=true;allowed=false;tick(300);assert(not running)",
'enter another car during permission callback':"callbackDelay=100;press();tick(10);VehicleState.currentVehicle=2;cache.vehicle=2;tick(200);assert(#calls==0)",
'exit during physical start does not move key':"press();tick(5);driver=0;cache.vehicle=false;cache.seat=false;VehicleState.currentVehicle=0;tick(200);assert(countEvent('pr_carkeys:server:keyLeftInVehicle')==0)",
'expiration during delayed start cancels confirmation':"press();tick(10);events['pr_carkeys:client:forceEngineOff'](101);tick(3500);assert(not running and countEvent('pr_carkeys:server:keyLeftInVehicle')==0 and state.pr_carkeys_ignition==false)",
'engine persists on exit without returning key':"running=true;state.pr_carkeys_ignition=true;cacheCallbacks.vehicle(1);exitVehicle();tick(1000);assert(running and exitPreserved and #calls==1 and calls[1].on and countEvent('pr_carkeys:server:returnKeyFromVehicle')==0)",
'seat cache may clear before vehicle exit cache':"running=true;state.pr_carkeys_ignition=true;cacheCallbacks.vehicle(1);cacheCallbacks.seat(false);driver=0;cache.vehicle=false;cache.seat=false;VehicleState.currentVehicle=0;cacheCallbacks.vehicle(false,1);assert(running and exitPreserved and #calls==1 and calls[1].on)",
'unoccupied engine is never restarted':"state.pr_carkeys_ignition=true;driver=0;cache.seat=false;cache.vehicle=false;VehicleState.currentVehicle=0;tick(5000);assert(not running and #calls==0)",
'single exit write retains engine without ped exit task':"running=true;state.pr_carkeys_ignition=true;cacheCallbacks.vehicle(1);assert(pedFlags[241]==false and #keepCalls==0);exitVehicle();tick(1000);assert(running and #calls==1 and calls[1].instant==false and #keepCalls==0 and pedFlags[241]==false)",
'keep-engine setting disabled':"Config.KeyInVehicle.keepVehicleEngineOn=false;running=true;cacheCallbacks.vehicle(1);exitVehicle();assert(not running and #calls==0 and #keepCalls==0)",
'engine off is not made persistent':"cacheCallbacks.vehicle(1);exitVehicle();assert(not running and #calls==0 and #keepCalls==0)",
'preexisting ped exit flag is cleared':"pedFlags[241]=true;running=true;state.pr_carkeys_ignition=true;cacheCallbacks.vehicle(1);assert(pedFlags[241]==false and pedFlags[429])",
'resource stop resets ped flags':"running=true;state.pr_carkeys_ignition=true;cacheCallbacks.vehicle(1);events.onResourceStop('pr_carkeys');assert(pedFlags[241]==false and pedFlags[429]==false)",
'W cannot start an engine':"cacheCallbacks.vehicle(1);assert(pedFlags[429] and not running);pressW();tick(50);assert(not running and #calls==0)",
'Z starts explicitly while automatic start remains blocked':"cacheCallbacks.vehicle(1);pressW();assert(not running);press();tick(300);assert(running and #calls==1 and calls[1].on and calls[1].auto==true and pedFlags[429])",

'normal shutdown returns key once':"running=true;press();tick(500);assert(not running and countEvent('pr_carkeys:server:returnKeyFromVehicle')==1)",
'engine relit during key callback is stopped again':"running=true;callbackDelay=100;relightOnReturn=true;press();tick(600);assert(not running and countEvent('pr_carkeys:server:returnKeyFromVehicle')==1 and #calls==2);for _,c in ipairs(calls) do assert(not c.on) end",
'loss of network control fails safely':"owner=false;press();tick(1200);assert(#calls==0 and PRCarkeys.engineTransitionVehicle==nil)",
'removing temporary key requests server access instead of shutdown':"running=true;events['pr_carkeys:client:removeTempKey']('ABC');assert(#calls==0 and countEvent('pr_carkeys:server:validateDriverSeat')==1)",
'inventory rebuild never directly shuts engine down':"running=true;events['pr_carkeys:client:forceInventoryRebuild']();assert(#calls==0 and countEvent('pr_carkeys:server:validateDriverSeat')==1)",
}
for name,case in cases.items():
 lua=LuaRuntime();lua.execute(fixture)
 for f in files:lua.execute((r/f).read_text(encoding='utf-8-sig'))
 try:lua.execute(case)
 except Exception: print('FAILED:',name);raise
 print('PASS:',name)
for p in r.rglob('*.lua'):
 if 'node_modules' in p.parts or 'install' in p.relative_to(r).parts: continue
 code=p.read_text(encoding='utf-8-sig')
 code=re.sub(r'`[A-Za-z0-9_]+`', '0', code)  # FiveM compile-time model hashes; Lua 5.4 uses a numeric placeholder.
 lua=LuaRuntime()
 try: lua.execute('assert(load(...))',code)
 except Exception: print('SYNTAX FAILED:',p); raise
print('All runtime Lua files compile under Lua 5.4 (FiveM model hash literals replaced for parsing only).')
print(len(cases),'full-module coroutine scenarios passed (GTA natives mocked).')
