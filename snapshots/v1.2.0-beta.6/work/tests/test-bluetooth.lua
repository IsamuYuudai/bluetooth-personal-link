local source = assert(loadfile(_TEST_MOD_ROOT .. '/init.lua', 't', {}))
local checks = {}
local function expect(value, message) if not value then error(message or 'assertion failed', 2) end end
local function check(name, callback) callback(); checks[#checks+1] = name; print('PASS ' .. name) end
local function copy(value)
  if type(value) ~= 'table' then return value end
  local out = {}; for k,v in pairs(value) do out[k] = copy(v) end; return out
end

local function fixture(config, options)
  options = options or {}
  local f = {events={},observers={},sounds={},stops={},logs={},writes={},now=100,config=copy(config),objects={},overrides=0,randomCalls=0,
    uiValues={},uiButtons={},uiTexts={},uiBegins=0,uiEnds=0,audioQueries=0,paused=options.paused==true,inMenu=options.inMenu==true,timeChanges=0,
    dynamicEvents={},resumes={},extCalls=0,dynamicQueues=0,audioOrder={},foreignSound={paused=false,resumes=0}}
  f.clips=copy(options.clips or {connected={'ncc_bluetooth_personallink_connected'},disconnected={'ncc_bluetooth_personallink_disconnected'}})
  local env = {}; setmetatable(env,{__index=_G})
  local function capture(class, method, callback)
    expect(type(class)=='string' and type(method)=='string' and type(callback)=='function','invalid observer registration')
    if options.menuHookThrows and class=='Audioware.LifecycleSubSystem' then error('simulated menu hook failure') end
    local key=class .. '.' .. method
    f.observers[key]=f.observers[key] or {}; table.insert(f.observers[key],callback)
  end
  local recordSound
  local function puppet(hash, player)
    local object={GetEntityID=function() return {hash=hash} end, IsPlayer=function() return player~=false end}
    function object:QueueEvent(event)
      expect(event and event.name and event.settings,'invalid dynamic event queued')
      if options.queueThrows then error('simulated queue failure')end
      f.dynamicQueues=f.dynamicQueues+1
      recordSound(event.name,self:GetEntityID(),'V','Regular',event.settings)
      event.queued=true
    end
    return object
  end
  f.player=puppet(101,true); f.npc=puppet(999,false); f.guest=puppet(202,true)
  f.puppet=puppet
  f.audio={}
  recordSound=function(event, entityID, emitter, dialogType, settings)
    if options.audioThrows or (options.throwEvents and options.throwEvents[event]) then error('simulated audio failure') end
    expect(type(event)=='string' and type(emitter)=='string','audio CName arguments invalid')
    expect(entityID.hash==f.player:GetEntityID().hash,'audio emitted for wrong player')
    expect(dialogType=='Regular','dialog type incorrect')
    expect(type(settings)=='table' and type(settings.volume)=='number','missing audio settings')
    expect(settings.volume>=0 and settings.volume<=10^(24/20),'unbounded boosted amplitude')
    expect(settings.affectedByTimeDilation==false,'announcement unexpectedly follows Sandevistan time')
    expect(settings.playbackRate==1 and settings.startPosition==0 and settings.loop==false and settings.panning==0,'audio defaults not explicitly initialized')
    f.sounds[#f.sounds+1]={event=event,entity=entityID.hash,emitter=emitter,settings=copy(settings),at=f.now}
  end
  function f.audio:Play(event, entityID, emitter, dialogType, settings)
    f.extCalls=f.extCalls+1
    f.audioOrder[#f.audioOrder+1]='play:'..event
    recordSound(event,entityID,emitter,dialogType,settings)
  end
  function f.audio:Stop(...)
    local args={...};f.stops[#f.stops+1]=args
    f.audioOrder[#f.audioOrder+1]='stop:'..tostring(args[1])
  end
  function f.audio:Duration(event)
    if options.durationThrows or (options.durationThrowEvents and options.durationThrowEvents[event]) then error('simulated duration query failure') end
    if options.durations and options.durations[event]~=nil then return options.durations[event] end
    return options.duration==nil and 3.279 or options.duration
  end
  function f.audio:Version() if options.versionThrows then error('simulated version query failure')end;return 'fixture-audioware-1.0'end
  local blackboardDefs={UI_System={IsInMenu='fixture-in-menu'}}
  env.Game={GetPlayer=function() if options.noPlayer then return nil end;return f.player end,
    GetAudioSystemExt=function() f.audioQueries=f.audioQueries+1;if options.audioMissing then return nil end return f.audio end,
    GetAudioSystem=function() return f.audio end,
    GetAllBlackboardDefs=function()return blackboardDefs end,
    GetBlackboardSystem=function()return{Get=function(_,definitions)
      expect(definitions==blackboardDefs.UI_System,'unexpected blackboard')
      return{GetBool=function(_,field)
        expect(field==blackboardDefs.UI_System.IsInMenu,'unexpected blackboard field')
        if options.menuQueryThrows then error('simulated menu query failure')end
        return f.inMenu
      end}
    end}end,
    GetTimeSystem=function()return{
      IsPausedState=function()if options.pauseQueryThrows then error('simulated pause query failure')end;return f.paused end,
      SetTimeDilation=function()f.timeChanges=f.timeChanges+1;error('time changes forbidden')end,
      UnsetTimeDilation=function()f.timeChanges=f.timeChanges+1;error('time changes forbidden')end
    }end}
  env.CName={new=function(s) return s end}
  env.Enum={new=function(class,value)expect(class=='scnDialogLineType' and value=='Regular','unexpected enum');return value end}
  env.scnDialogLineType={Regular='Regular'}
  env.NewObject=function(class) expect(class=='Audioware.AudioSettingsExt','unexpected engine object construction');return {playbackRate=0} end
  env.GetSingleton=function(class)
    expect(class=='Audioware.DynamicSoundEvent','unexpected singleton requested')
    if options.dynamicMissing then return nil end
    if options.factoryThrows then error('simulated factory lookup failure')end
    local factory={}
    function factory:Create(name,settings)
      expect(type(name)=='string' and type(settings)=='table','dynamic factory parameters invalid')
      if options.createThrows then error('simulated event creation failure')end
      if options.createReturnsNil then return nil end
      local event={name=name,settings=settings,paused=false,stopped=false}
      function event:Stop()
        self.stopped=true
        f.stops[#f.stops+1]={self.name}
      end
      function event:Resume()
        if options.resumeThrows then error('simulated resume failure')end
        expect(self.queued and not self.stopped,'resumed an unqueued or stopped event')
        self.paused=false
        f.resumes[#f.resumes+1]=self
      end
      f.dynamicEvents[#f.dynamicEvents+1]=event
      return event
    end
    return factory
  end
  env.IsDefined=function(value) return value~=nil end
  env.registerForEvent=function(name,callback) f.events[name]=callback end
  env.Observe= capture; env.ObserveBefore=capture; env.ObserveAfter=capture
  env.Override=function() f.overrides=f.overrides+1;error('gameplay override is not allowed in this addon') end
  env.registerHotkey=function() end
  env.GetMod=function() return nil end
  env.print=function(...) local words={...};for i,v in ipairs(words)do words[i]=tostring(v)end;f.logs[#f.logs+1]=table.concat(words,' ')end
  env.os={time=function()return f.now end,clock=function()return f.now end}
  env.math=setmetatable({random=function()f.randomCalls=f.randomCalls+1;error('global RNG consumed')end,
    randomseed=function()f.randomCalls=f.randomCalls+1;error('global RNG reseeded')end},{__index=math})
  env.json={decode=function(text)
      if text=='fixture clips' then if options.badClipsJSON then error('invalid clips JSON')end;return copy(f.clips)end
      if options.badJSON then error('invalid JSON')end;return copy(f.config or {})end,
    encode=function(payload)
      if options.encodeThrows then error('simulated JSON encode failure')end
      f.encoded=copy(payload);return 'fixture encoded settings'
    end}
  env.io={open=function(name,mode)
    expect(name=='settings.json' or name=='clips.json','unexpected file access: '..tostring(name))
    if name=='clips.json' then
      if options.missingClips then return nil end
      return {read=function()return 'fixture clips'end,close=function()end}
    end
    if mode=='r' then if f.config==nil and not options.badJSON then return nil end;return {read=function()return 'fixture settings'end,close=function()end} end
    if options.openWriteFail then return nil,'simulated read-only settings'end
    local writer={}
    function writer:write(text)
      if options.writeFail then return nil,'simulated disk failure'end
      f.writes[#f.writes+1]=text;self.written=true;return self
    end
    function writer:close()
      if options.closeFail then return nil,'simulated close failure'end
      if self.written then f.config=copy(f.encoded)end
      return true
    end
    return writer
  end}
  local function uiValue(label,current)
    local selected=f.uiValues[label]
    if selected then f.uiValues[label]=nil;return selected.value,true end
    return current,false
  end
  env.ImGuiWindowFlags={NoCollapse=32}
  env.ImGui={
    Begin=function()f.uiBegins=f.uiBegins+1;if options.beginThrows then error('simulated Begin failure')end;return not options.beginClosed end,
    End=function()f.uiEnds=f.uiEnds+1 end,
    Text=function(text)if options.uiTextThrows then error('simulated UI text failure')end;f.uiTexts[#f.uiTexts+1]=text end,
    TextWrapped=function(text)f.uiTexts[#f.uiTexts+1]=text end,
    Separator=function()end,
    Checkbox=uiValue,SliderFloat=uiValue,SliderInt=uiValue,
    Button=function(label)local pressed=f.uiButtons[label];f.uiButtons[label]=nil;return pressed==true end
  }
  local loaded=assert(loadfile(_TEST_MOD_ROOT..'/init.lua','t',env)); f.api=loaded()
  function f.emit(name,...) if f.events[name]then return f.events[name](...)end end
  function f.observe(name,...) for _,cb in ipairs(f.observers[name] or {})do cb(...)end end
  function f.advance(seconds)f.now=f.now+seconds;f.emit('onUpdate',seconds)end
  function f.device(hash, connected)
    local d={hash=hash,connected=connected~=false}
    function d:GetEntityID()return{hash=self.hash}end
    function d:GetDevicePS()return{IsPersonalLinkConnected=function()return d.connected end}end
    return d
  end
  function f.action(executor,completed)
    return{GetExecutor=function()return executor end,IsCompleted=function()return completed~=false end}
  end
  function f.toggle(d,toggle,who)f.observe('Device.TogglePersonalLink',d,toggle,who or f.player)end
  function f.complete(d,who,completed)f.observe('Device.OnTogglePersonalLink',d,f.action(who or f.player,completed))end
  function f.connect(d)f.toggle(d,true);f.complete(d)end
  function f.menu(opened)
    f.inMenu=opened
    f.foreignSound.paused=opened
    for _,event in ipairs(f.dynamicEvents)do if event.queued and not event.stopped then event.paused=opened end end
    f.observe('Audioware.LifecycleSubSystem.OnMenu',{},opened)
  end
  f.emit('onInit')
  return f
end

check('connecting is silent; completed connected local action plays exactly once',function()
  local f=fixture();local d=f.device(1)
  f.toggle(d,true);expect(#f.sounds==0,'animation start incorrectly announced success')
  f.complete(d);expect(#f.sounds==1,'successful connection missing')
  expect(f.sounds[1].event=='ncc_bluetooth_personallink_connected','wrong connection event')
  expect(f.sounds[1].settings.volume==0.8,'default volume wrong')
  expect(f.api.status().announcements==1 and f.overrides==0,'game logic replaced or counter incorrect')
  f.complete(d);f.toggle(d,true);f.complete(d);expect(#f.sounds==1,'duplicate event announced again')
end)

check('incomplete, disconnected, uninitiated and nil-executor completions stay silent',function()
  local f=fixture();local d=f.device(1)
  f.complete(d);expect(#f.sounds==0,'uninitiated completion announced')
  f.toggle(d,true);f.complete(d,f.player,false);expect(#f.sounds==0,'incomplete action announced')
  d.connected=false;f.complete(d);expect(#f.sounds==0,'disconnected PS announced')
  d.connected=true
  f.observe('Device.OnTogglePersonalLink',d,f.action(nil,true));expect(#f.sounds==0,'missing executor guessed local')
  f.complete(d);expect(#f.sounds==1,'valid later completion was lost')
end)

check('NPC and player-like remote replicas never trigger this PC audio',function()
  local f=fixture();local d=f.device(1)
  for _,who in ipairs({f.npc,f.guest})do f.toggle(d,true,who);f.complete(d,who)end
  expect(#f.sounds==0 and f.api.status().pendingDevice==nil,'nonlocal initiation leaked')
  f.toggle(d,true);f.complete(d,f.guest);expect(#f.sounds==0,'remote completion stole local pending')
  f.complete(d);expect(#f.sounds==1,'local completion suppressed')
end)

check('cancelled connection has no disconnect announcement',function()
  local f=fixture({disconnectAnnouncement=true});local d=f.device(1)
  f.toggle(d,true);f.toggle(d,false);f.complete(d)
  expect(#f.sounds==0 and f.api.status().pendingDevice==nil,'failed/cancelled connection announced')
end)

check('default disconnection is silent and rapid reconnect cannot overlap',function()
  local f=fixture();local d=f.device(1)
  f.connect(d);f.toggle(d,false);expect(#f.sounds==1,'default disconnection was audible')
  f.connect(d);expect(#f.sounds==1,'rapid reconnect overlapped audio')
  f.toggle(d,false);f.advance(5);f.connect(d);expect(#f.sounds==2,'later reconnect did not recover')
end)

check('different devices share cooldown and unrelated exits cannot clear active device',function()
  local f=fixture({cooldownSeconds=10});local a,b,c=f.device(1),f.device(2),f.device(3)
  f.connect(a);f.toggle(b,false);expect(f.api.status().activeDevice=='1','unrelated exit cleared active device')
  f.advance(6);f.connect(b);expect(#f.sounds==1,'different device bypassed global cooldown')
  f.advance(5);f.connect(c);expect(#f.sounds==2,'global cooldown did not release')
end)

check('clip duration safety exceeds short configured cooldown',function()
  local f=fixture({cooldownSeconds=0},{duration=7.1});local a,b,c=f.device(1),f.device(2),f.device(3)
  f.connect(a);f.advance(8);f.connect(b);expect(#f.sounds==1,'duration ceil plus guard second ignored')
  f.advance(1);f.connect(c);expect(#f.sounds==2,'duration safety never released')
end)

check('optional disconnect plays once only for an established local device',function()
  local f=fixture({disconnectAnnouncement=true});local d=f.device(1)
  f.connect(d);f.advance(5);f.toggle(d,false);f.toggle(d,false)
  expect(#f.sounds==2 and f.sounds[2].event=='ncc_bluetooth_personallink_disconnected','disconnect missing or duplicated')
end)

check('disable and zero-volume settings are silent; disabling stops active sound',function()
  local f=fixture({enabled=false});f.connect(f.device(1));expect(#f.sounds==0,'disabled addon played')
  expect(f.api.setEnabled(true)==true,'enable control failed');expect(f.api.test()==true,'preview after enable failed')
  f.api.setEnabled(false);expect(#f.stops==1,'disable did not stop sound')
  expect(f.api.setEnabled('true')==false,'invalid enable type accepted')
  local mute=fixture({volume=0});mute.connect(mute.device(2));expect(#mute.sounds==0,'muted addon played')
end)

check('malformed settings default safely and numeric inputs clamp',function()
  local f=fixture({}, {badJSON=true});expect(f.api.status().enabled and f.api.status().volume==0.8,'invalid JSON did not default')
  f.connect(f.device(1));expect(#f.sounds==1,'invalid JSON broke addon')
  local clamped=fixture({volume=5,cooldownSeconds=-100,enabled='bad',disconnectAnnouncement='bad'})
  local s=clamped.api.status();expect(s.volume==1 and s.cooldownSeconds==0 and s.enabled and not s.disconnectAnnouncement,'settings validation wrong')
  local invalid=fixture({volume=0/0,cooldownSeconds=math.huge});expect(invalid.api.status().volume==0.8 and invalid.api.status().cooldownSeconds==4,'nonfinite settings accepted')
end)

check('missing audio, invalid duration and playback errors cannot escape game observers',function()
  for _,opts in ipairs({{audioMissing=true},{duration=0},{duration=-1},{duration=0/0},{duration=math.huge},{audioThrows=true}})do
    local f=fixture(nil,opts);local d=f.device(1)
    local ok=pcall(function()f.connect(d);f.complete(d)end)
    expect(ok and #f.sounds==0 and f.api.status().announcements==0,'audio failure escaped or counted playback')
  end
end)

check('transient audio failure does not consume cooldown or prevent later preview',function()
  local options={audioMissing=true};local f=fixture(nil,options)
  expect(f.api.test()==false and f.api.status().announcements==0,'missing audio preview succeeded')
  options.audioMissing=false
  expect(f.api.test()==true and #f.sounds==1,'transient audio failure consumed cooldown')
end)

check('no local player and invalid device identity stay silent',function()
  local f=fixture(nil,{noPlayer=true});expect(f.api.test()==false,'preview without local player succeeded')
  local valid=fixture();valid.connect(valid.device(0));expect(#valid.sounds==0,'zero entity identity accepted')
end)

check('detach, attach and local-player replacement clear stale device state and stop audio',function()
  local f=fixture();local d=f.device(1);f.connect(d)
  f.observe('PlayerPuppet.OnDetach',f.guest);expect(f.api.status().activeDevice=='1','remote detach cleared local state')
  f.observe('PlayerPuppet.OnDetach',f.player);expect(f.api.status().activeDevice==nil and #f.stops==1,'local detach did not reset')
  f.observe('PlayerPuppet.OnGameAttached',f.player);f.connect(d);expect(#f.sounds==2,'attached player retained stale device')
  f.player=f.puppet(303,true);f.advance(1);expect(f.api.status().activeDevice==nil,'new local player retained old state')
  f.connect(f.device(2));expect(#f.sounds==3,'replacement player could not connect')
  f.emit('onShutdown');expect(f.api.status().activeDevice==nil,'shutdown did not reset')
end)

check('backward wall-clock movement does not bypass cooldown',function()
  local f=fixture({cooldownSeconds=10});local a,b,c=f.device(1),f.device(2),f.device(3)
  f.connect(a);f.now=50;f.connect(b);expect(#f.sounds==1,'clock rollback bypassed cooldown')
  f.now=111;f.connect(c);expect(#f.sounds==2,'clock recovery failed')
end)

check('settings reload preserves runtime controls and does not mutate gameplay methods',function()
  local f=fixture();f.connect(f.device(1));f.config={enabled=true,volume=0,cooldownSeconds=30,disconnectAnnouncement=true}
  f.api.reloadSettings();local s=f.api.status()
  expect(s.volume==0 and s.cooldownSeconds==30 and s.disconnectAnnouncement,'reload did not apply validated preferences')
  expect(#f.stops==1 and f.overrides==0,'reload failed to stop muted audio or changed game logic')
end)

check('shuffle cycles cover every recording and never repeat at cycle boundaries',function()
  local f=fixture(nil,{clips={connected={'clip_a','clip_b','clip_c'},disconnected={}}})
  local last=nil
  for cycle=1,20 do
    local seen={}
    for i=1,3 do
      expect(f.api.test(),'random preview failed')
      local name=f.sounds[#f.sounds].event
      expect(not seen[name],'recording repeated before full cycle')
      expect(name~=last,'adjacent recording repeated')
      seen[name]=true;last=name;f.advance(5)
    end
    expect(seen.clip_a and seen.clip_b and seen.clip_c,'pool member omitted')
  end
  expect(f.randomCalls==0,'another mod random stream was changed')
  expect(f.api.status().connectedClips==3 and f.api.status().lastEvent==last,'random status is wrong')
end)

check('unavailable recordings are skipped and a single available recording remains usable',function()
  local f=fixture(nil,{clips={connected={'missing','clip_b','clip_c'},disconnected={}},durations={missing=0}})
  for i=1,8 do expect(f.api.test(),'missing entry blocked healthy recording');expect(f.sounds[#f.sounds].event~='missing','missing audio played');f.advance(5)end
  local g=fixture(nil,{clips={connected={'missing','only'},disconnected={}},durations={missing=0}})
  for i=1,3 do expect(g.api.test() and g.sounds[#g.sounds].event=='only','single healthy recording failed');g.advance(5)end
end)

check('complete audio failure preserves the next selection and does not consume a shuffle position',function()
  local pool={connected={'clip_a','clip_b','clip_c'},disconnected={}}
  local control=fixture(nil,{clips=pool});expect(control.api.test(),'control selection failed')
  local opts={clips=pool,duration=0};local f=fixture(nil,opts)
  expect(f.api.test()==false,'invalid recordings played')
  expect(f.api.status().connectedRemaining==0 and f.api.status().lastEvent==nil,'failed bank consumed selection')
  opts.duration=3.279;expect(f.api.test(),'bank recovery failed')
  expect(f.sounds[1].event==control.sounds[1].event,'failed bank advanced private random state')
  local throwing={clips=pool,audioThrows=true};local g=fixture(nil,throwing)
  expect(g.api.test()==false,'throwing bank played');throwing.audioThrows=false
  expect(g.api.test() and g.sounds[1].event==control.sounds[1].event,'playback failure consumed shuffle position')
end)

check('pool validation removes duplicates and rejects unsafe or missing definitions without synthetic fallback',function()
  local f=fixture(nil,{clips={connected={'clip_a','clip_a','../escape','has spaces',55,'clip_b'},disconnected={}}})
  expect(f.api.status().connectedClips==2,'invalid or duplicate IDs accepted')
  expect(f.api.test(),'validated pool unusable')
  for _,opts in ipairs({{clips={connected={},disconnected={}}},{badClipsJSON=true},{missingClips=true}}) do
    local g=fixture(nil,opts);expect(g.api.status().connectedClips==0 and not g.api.test() and #g.sounds==0,'old synthetic fallback was used')
  end
end)

check('stop targets the actual randomly chosen event and clip-specific durations prevent overlap',function()
  local f=fixture({cooldownSeconds=0},{clips={connected={'clip_a','clip_b'},disconnected={}},durations={clip_a=12,clip_b=12}})
  expect(f.api.test(),'preview failed');local chosen=f.sounds[1].event
  f.advance(12);expect(not f.api.test(),'chosen long recording overlapped')
  f.api.setEnabled(false);expect(f.stops[1][1]==chosen,'stopped a fixed or unrelated audio event')
  f.api.setEnabled(true);f.advance(1);expect(f.api.test(),'duration guard never released')
end)

check('playback errors skip broken clips without trapping the remaining shuffle bag',function()
  local options={clips={connected={'clip_a','clip_b','clip_c'},disconnected={}},throwEvents={}}
  local f=fixture(nil,options)
  expect(f.api.test(),'first healthy preview failed');local healthy=f.sounds[1].event
  for _,name in ipairs({'clip_a','clip_b','clip_c'})do options.throwEvents[name]=name~=healthy end
  f.advance(5);expect(f.api.test(),'broken remaining bag trapped healthy recording from earlier cycle')
  expect(f.sounds[2].event==healthy,'failed events were counted as played')
end)

check('CET panel is overlay-only, can be hidden, and balances closed windows',function()
  local f=fixture()
  f.emit('onDraw');expect(f.uiBegins==0,'panel drew outside the CET overlay')
  f.emit('onOverlayOpen');f.emit('onDraw')
  expect(f.uiBegins==1 and f.uiEnds==1 and f.api.status().overlayOpen,'panel did not open cleanly')
  expect(f.audioQueries==0 and #f.writes==0,'drawing the panel queried audio or wrote settings')
  f.emit('onOverlayClose');f.emit('onDraw');expect(f.uiBegins==1,'panel stayed open during gameplay')
  f.emit('onOverlayOpen');f.api.showPanel(false);f.emit('onDraw');expect(f.uiBegins==1,'hide panel failed')
  expect(not f.api.showPanel('yes'),'invalid panel argument accepted')
  f.api.showPanel();f.emit('onDraw');expect(f.uiBegins==2 and f.uiEnds==2,'show panel default failed')
  local g=fixture(nil,{beginClosed=true});g.emit('onOverlayOpen');g.emit('onDraw')
  expect(g.uiBegins==1 and g.uiEnds==1 and not g.api.status().panelVisible,'closed panel not balanced/hidden')
end)

check('panel controls apply safely and persist only after explicit Save',function()
  local f=fixture();f.connect(f.device(1));f.emit('onOverlayOpen')
  f.uiValues={Enabled={value=false},Volume={value=2.5},['Cooldown (seconds)']={value=100},['Disconnect announcements']={value=true}}
  f.emit('onDraw')
  local state=f.api.status()
  expect(not state.enabled and state.volume==1 and state.cooldownSeconds==30 and state.disconnectAnnouncement,'panel input was not validated')
  expect(#f.stops==1 and state.settingsDirty and #f.writes==0,'panel did not stop disabled audio or wrote before Save')
  f.uiButtons['Save settings']=true;f.emit('onDraw')
  expect(#f.writes==1 and not f.api.status().settingsDirty,'Save did not persist once')
  expect(f.encoded.enabled==false and f.encoded.volume==1 and f.encoded.cooldownSeconds==30 and f.encoded.disconnectAnnouncement,'saved settings differ from panel')
  expect(f.encoded.connectedClips==nil and f.encoded.lastEvent==nil,'runtime state leaked into settings')
  f.config={enabled=true,volume=0.2,cooldownSeconds=6,disconnectAnnouncement=false}
  f.uiButtons['Reload saved settings']=true;f.emit('onDraw')
  expect(f.api.status().volume==0.2 and not f.api.status().settingsDirty,'Reload did not restore saved settings')
end)

check('panel preview and sound list reload use the public audio pool without filesystem writes',function()
  local f=fixture();f.emit('onOverlayOpen');f.uiButtons['Test connection sound']=true;f.emit('onDraw')
  expect(#f.sounds==0 and f.api.status().pendingPreview,'overlay preview did not queue')
  expect(table.concat(f.uiTexts,' '):match('Test queued'),'queued result was not shown in the panel')
  f.emit('onOverlayClose');f.advance(0)
  expect(#f.sounds==1 and f.api.status().lastEvent==f.sounds[1].event,'preview button did not use the selected recording')
  f.clips={connected={'new_clip_1','new_clip_2'},disconnected={}}
  f.emit('onOverlayOpen')
  f.uiButtons['Reload sound lists']=true;f.emit('onDraw')
  expect(f.api.status().connectedClips==2 and #f.writes==0,'pool reload did not read only the pool file')
  local g=fixture(nil,{audioMissing=true});g.emit('onOverlayOpen');g.uiButtons['Test connection sound']=true;g.emit('onDraw')
  g.emit('onOverlayClose');g.advance(0);g.emit('onOverlayOpen');g.emit('onDraw')
  expect(g.api.status().lastIssue:match('Audioware'),'missing audio dependency did not produce a readable hint')
  expect(table.concat(g.uiTexts,' '):match('Requires Audioware'),'panel lacks dependency guidance')
end)

check('settings persistence failures are contained and never touch unrelated files',function()
  for _,options in ipairs({{openWriteFail=true},{writeFail=true},{closeFail=true},{encodeThrows=true}})do
    local f=fixture(nil,options);f.api.setEnabled(false)
    expect(not f.api.saveSettings() and f.api.status().settingsDirty,'failed Save was reported as success')
    expect(not f.api.status().enabled,'failed Save changed the live setting')
  end
  local f=fixture();f.api.setEnabled(false)
  expect(f.api.saveSettings() and f.config.enabled==false,'false was not persisted by the console API')
end)

check('panel errors cannot escape callbacks and an opened ImGui window is ended',function()
  local f=fixture(nil,{uiTextThrows=true});f.emit('onOverlayOpen')
  f.emit('onDraw');f.emit('onDraw')
  expect(f.uiBegins==2 and f.uiEnds==2,'UI error left the ImGui stack unbalanced')
  expect(#f.logs==2,'repeated UI error spammed logs')
  local g=fixture(nil,{beginThrows=true});g.emit('onOverlayOpen');g.emit('onDraw')
  expect(g.uiEnds==0,'End was called without a successful Begin')
end)

check('manual preview queues through pause and overlay, then runs once on resume without time changes',function()
  local f=fixture(nil,{paused=true})
  expect(not f.api.test() and f.api.status().pendingPreview,'paused preview was not queued')
  expect(#f.sounds==0 and table.concat(f.logs,' '):match('Test queued'),'queued preview missing readable outcome')
  f.advance(5);expect(#f.sounds==0,'preview ran while game paused')
  f.emit('onOverlayOpen');f.paused=false;f.advance(1);expect(#f.sounds==0,'preview ran before CET closed')
  f.emit('onOverlayClose');f.advance(1)
  expect(#f.sounds==1 and not f.api.status().pendingPreview,'preview did not run once after resume')
  f.advance(6);expect(#f.sounds==1 and f.timeChanges==0,'preview repeated or altered time dilation')
  expect(table.concat(f.logs,' '):match('Playback requested') and table.concat(f.logs,' '):match('rate 1.0'),'actual preview outcome did not log')
end)

check('queued previews expire or clear on reset/disable, with no delayed sounds',function()
  local f=fixture(nil,{paused=true});f.api.test();f.advance(30)
  expect(not f.api.status().pendingPreview and #f.sounds==0,'queued preview did not expire')
  f.paused=false;f.advance(1);expect(#f.sounds==0,'expired preview played later')
  local g=fixture(nil,{paused=true});g.api.test();g.observe('PlayerPuppet.OnDetach',g.player)
  expect(not g.api.status().pendingPreview,'session reset left a queued preview')
  g.paused=false;g.advance(1);expect(#g.sounds==0,'reset preview played in another session')
  local h=fixture(nil,{paused=true});h.api.test();h.api.setEnabled(false)
  expect(not h.api.status().pendingPreview,'disabling did not cancel queued preview')
end)

check('preview retains native Duration and Play errors and reports failure outcomes',function()
  local f=fixture(nil,{durationThrows=true})
  expect(not f.api.test() and f.api.status().lastIssue:match('simulated duration query failure'),'Duration error discarded')
  expect(table.concat(f.logs,' '):match('Preview: Not played'),'failed preview outcome missing')
  local g=fixture(nil,{audioThrows=true})
  expect(not g.api.test() and g.api.status().lastIssue:match('simulated audio failure'),'Play error discarded')
  local h=fixture(nil,{clips={connected={'bad','good'},disconnected={}},durationThrowEvents={bad=true}})
  expect(h.api.test() and h.api.status().lastIssue:match('simulated duration query failure'),'skipped event error hidden by successful fallback')
end)

check('diagnostic is read-only and reports version, duration, pause, player and requested rate',function()
  local f=fixture({volume=0.4});local before=f.api.status();local d=f.api.diagnostic()
  expect(d.playerPresent and d.playerEntity=='101' and d.paused==false and d.inMenu==false,'player, menu or pause diagnostic wrong')
  expect(d.audioAvailable and d.audioVersion=='fixture-audioware-1.0','audio version diagnostic missing')
  expect(d.constructedPlaybackRate==0 and d.requestedPlaybackRate==1 and d.requestedSettings.playbackRate==1,'rate default diagnostic/fix missing')
  expect(d.config.volume==0.4 and #d.recordings==1 and d.recordings[1].durationSeconds==3.279,'configuration/duration diagnostic wrong')
  expect(#f.sounds==0 and #f.stops==0 and #f.writes==0 and f.api.status().connectedRemaining==before.connectedRemaining,'diagnostic changed sound or selection state')
  local g=fixture(nil,{durationThrows=true,versionThrows=true,pauseQueryThrows=true,menuQueryThrows=true})
  local failure=g.api.diagnostic()
  expect(failure.pauseError:match('simulated pause query failure') and failure.menuError:match('simulated menu query failure') and failure.recordings[1].error:match('simulated duration query failure') and failure.audioVersionError:match('simulated version query failure'),'diagnostic discarded native errors')
end)

check('unknown pause state keeps manual preview queued until safely resumed',function()
  local options={pauseQueryThrows=true};local f=fixture(nil,options)
  f.api.test();f.advance(2)
  expect(f.api.status().pendingPreview and #f.sounds==0 and f.api.status().lastIssue:match('pause query failure'),'unknown pause state treated as unpaused')
  options.pauseQueryThrows=false;f.advance(1)
  expect(#f.sounds==1 and not f.api.status().pendingPreview and f.timeChanges==0,'preview did not recover from transient pause query failure')
end)

check('unpaused co-op menus still hold queued previews until the Audioware menu state clears',function()
  local f=fixture(nil,{inMenu=true})
  expect(not f.api.test() and f.api.status().pendingPreview,'unpaused game menu did not queue')
  expect(f.api.diagnostic().paused==false and f.api.diagnostic().inMenu==true,'co-op menu diagnostics incorrect')
  f.advance(3);expect(#f.sounds==0,'preview consumed while Audioware still sees a menu')
  f.inMenu=false;f.advance(1)
  expect(#f.sounds==1 and not f.api.status().pendingPreview and f.timeChanges==0,'preview failed after menu closed')
  local options={menuQueryThrows=true};local g=fixture(nil,options)
  g.api.test();g.advance(2)
  expect(g.api.status().pendingPreview and #g.sounds==0 and g.api.status().lastIssue:match('menu query failure'),'unknown menu state treated as closed')
  options.menuQueryThrows=false;g.advance(1);expect(#g.sounds==1,'menu query recovery failed')
end)

check('tracked playback preserves local owner and settings without duplicate Ext playback',function()
  local f=fixture({volume=0.35});f.connect(f.device(1))
  expect(#f.sounds==1 and f.dynamicQueues==1 and f.extCalls==0,'tracked path was missing or duplicated through Ext')
  expect(f.sounds[1].entity==101 and f.sounds[1].settings.volume==0.35 and f.sounds[1].settings.affectedByTimeDilation==false,'tracked owner or settings changed')
  local s=f.api.status();expect(s.dynamicPlaybackAvailable and s.lastBackend=='dynamic' and s.menuResumeRequests==0,'tracked status incorrect')
  expect(f.api.diagnostic().dynamicPlaybackAvailable,'tracked diagnostic unavailable')
end)

check('menu entry after connection resumes only this addon handle and never creates another sound',function()
  local f=fixture();f.connect(f.device(1));local own=f.dynamicEvents[1]
  f.menu(true)
  expect(not own.paused and #f.resumes==1 and f.resumes[1]==own,'connection sound stayed paused on menu entry')
  expect(f.foreignSound.paused and f.foreignSound.resumes==0,'unrelated audio was resumed')
  expect(#f.sounds==1 and f.api.status().announcements==1 and f.api.status().menuResumeRequests==1,'resume replayed the announcement')
  expect(f.api.status().audioMenuOpen and f.timeChanges==0 and f.overrides==0 and #f.writes==0,'menu fix changed gameplay, time or files')
  f.menu(false);expect(#f.resumes==1 and not f.api.status().audioMenuOpen,'menu close requested unnecessary addon resume')
end)

check('menu entry before connection is covered after the new tracked event is queued',function()
  local f=fixture();f.menu(true);expect(#f.resumes==0,'menu entry without a sound resumed something')
  f.connect(f.device(1));local own=f.dynamicEvents[1]
  expect(own.queued and not own.paused and #f.resumes==1 and f.resumes[1]==own,'already-open menu did not cover the newly queued sound')
  expect(f.foreignSound.paused and #f.sounds==1 and f.api.status().announcements==1,'already-open menu replayed or unpaused unrelated audio')
end)

check('expired disabled detached replaced and shutdown handles cannot be resumed by later menus',function()
  local expired=fixture();expired.connect(expired.device(1));expired.advance(5);expired.menu(true)
  expect(#expired.resumes==0,'menu resumed a sound after its playback window')
  for _,mode in ipairs({'disable','detach','replace','shutdown'})do
    local f=fixture();f.connect(f.device(1));local own=f.dynamicEvents[1]
    if mode=='disable' then f.api.setEnabled(false)
    elseif mode=='detach' then f.observe('PlayerPuppet.OnDetach',f.player)
    elseif mode=='replace' then f.player=f.puppet(303,true);f.advance(0)
    else f.emit('onShutdown')end
    f.menu(true)
    expect(own.stopped and #f.resumes==0,'stale handle resumed after '..mode)
  end
end)

check('resume failures remain contained and do not fall back to global audio or alter time',function()
  local f=fixture(nil,{resumeThrows=true});f.connect(f.device(1))
  expect(pcall(function()f.menu(true);f.menu(true)end),'native resume error escaped the observer')
  expect(f.api.status().lastIssue:match('simulated resume failure'),'resume error was hidden')
  expect(#f.sounds==1 and f.extCalls==0 and f.timeChanges==0 and f.foreignSound.paused,'resume failure duplicated sound or changed other systems')
end)

check('missing tracked API or menu hook falls back to Ext without killing the newly queued repeated clip',function()
  for _,options in ipairs({{dynamicMissing=true},{factoryThrows=true},{menuHookThrows=true}})do
    local f=fixture(nil,options)
    expect(f.api.test(),'first fallback preview failed');f.advance(5);expect(f.api.test(),'second fallback preview failed')
    local name=f.sounds[1].event
    expect(f.extCalls==2 and f.dynamicQueues==0 and f.api.status().lastBackend=='ext','availability fallback was not exclusively Ext')
    expect(f.audioOrder[1]=='play:'..name and f.audioOrder[2]=='stop:'..name and f.audioOrder[3]=='play:'..name,'fallback stopped a fresh same-name event instead of the previous one')
    expect(not f.api.status().dynamicPlaybackAvailable,'unavailable dynamic path reported usable')
  end
end)

check('runtime tracked creation and queue failures stay errors rather than duplicating through Ext',function()
  for _,options in ipairs({{createThrows=true},{createReturnsNil=true},{queueThrows=true}})do
    local f=fixture(nil,options)
    expect(not f.api.test() and #f.sounds==0 and f.extCalls==0 and f.api.status().announcements==0,'tracked runtime failure was counted or duplicated')
    expect(f.api.status().lastIssue~=nil,'tracked runtime failure was hidden')
    if #f.dynamicEvents>0 then expect(f.dynamicEvents[1].stopped,'failed queued event reference was not stopped')end
  end
end)

check('missing boost preserves prior volume and explicit gain changes only the emitted amplitude',function()
  local plain=fixture({volume=0.5});expect(plain.api.test(),'default-gain preview failed')
  expect(plain.api.status().gainDb==0 and plain.sounds[1].settings.volume==0.5,'missing gain changed prior audio level')
  local f=fixture({volume=0.5,gainDb=10});expect(f.api.test(),'boosted preview failed')
  local expected=0.5*10^(10/20)
  expect(math.abs(f.sounds[1].settings.volume-expected)<1e-9,'10dB boost was not applied as linear amplitude')
  local s=f.api.status();local d=f.api.diagnostic()
  expect(s.volume==0.5 and s.gainDb==10 and math.abs(s.effectiveVolume-expected)<1e-9,'boost altered the base volume or status is incorrect')
  expect(d.config.gainDb==10 and math.abs(d.requestedSettings.volume-expected)<1e-9 and math.abs(d.effectiveVolume-expected)<1e-9,'boost diagnostics do not match requested audio')
  expect(f.timeChanges==0 and f.overrides==0 and #f.writes==0,'boost changed gameplay, time or persisted without Save')
end)

check('boost is clamped to 0 through 24dB and malformed or nonfinite values use zero',function()
  for _,case in ipairs({{value=99,want=24},{value=-5,want=0},{value='10',want=0},{value=0/0,want=0},{value=math.huge,want=0},{value=-math.huge,want=0}})do
    local f=fixture({volume=1,gainDb=case.value})
    expect(f.api.status().gainDb==case.want,'invalid gain did not clamp or default safely')
    expect(f.api.test(),'bounded gain prevented playback')
    expect(math.abs(f.sounds[1].settings.volume-10^(case.want/20))<1e-9,'bounded gain produced an incorrect amplitude')
  end
  local max=fixture({volume=5,gainDb=24});expect(max.api.test(),'maximum boost preview failed')
  expect(max.api.status().volume==1 and math.abs(max.sounds[1].settings.volume-10^(24/20))<1e-9,'maximum gain escaped the base-volume or boost limits')
end)

check('boost never unmutes zero volume or disabled notifications',function()
  local muted=fixture({volume=0,gainDb=24});muted.connect(muted.device(1))
  expect(not muted.api.test() and #muted.sounds==0,'gain bypassed zero-volume silence')
  expect(muted.api.status().effectiveVolume==0 and muted.api.diagnostic().requestedSettings.volume==0,'zero-volume boost was not exactly zero')
  local disabled=fixture({enabled=false,volume=1,gainDb=24});disabled.connect(disabled.device(2))
  expect(not disabled.api.test() and #disabled.sounds==0,'gain bypassed disabled announcements')
end)

check('boost UI changes are bounded apply to the next sound and persist only after Save',function()
  local f=fixture({volume=0.5,gainDb=0});expect(f.api.test(),'initial preview failed')
  f.emit('onOverlayOpen');f.uiValues['Audio boost (dB)']={value=10};f.emit('onDraw')
  expect(f.api.status().gainDb==10 and f.api.status().settingsDirty and #f.writes==0,'boost slider did not update only the runtime setting')
  expect(f.sounds[1].settings.volume==0.5,'boost slider altered an already queued notification')
  f.uiButtons['Save settings']=true;f.emit('onDraw')
  expect(#f.writes==1 and f.encoded.gainDb==10 and not f.api.status().settingsDirty,'boost was not persisted through explicit Save')
  f.config={volume=1,gainDb=99};f.api.reloadSettings()
  expect(f.api.status().gainDb==24 and not f.api.status().settingsDirty,'reloaded gain was not bounded')
  f.emit('onOverlayClose');f.advance(5);expect(f.api.test(),'preview after gain reload failed')
  expect(math.abs(f.sounds[2].settings.volume-10^(24/20))<1e-9,'reloaded gain did not apply to the next sound')
  f.emit('onOverlayOpen');f.uiValues['Audio boost (dB)']={value=-9};f.emit('onDraw')
  expect(f.api.status().gainDb==0,'negative slider input escaped validation')
  f.uiValues['Audio boost (dB)']={value=99};f.emit('onDraw')
  expect(f.api.status().gainDb==24,'oversized slider input escaped validation')
end)

check('tracked and Ext fallback playback use the same bounded boosted amplitude',function()
  local settings={volume=0.7,gainDb=6}
  local tracked=fixture(settings);local fallback=fixture(settings,{dynamicMissing=true})
  expect(tracked.api.test() and fallback.api.test(),'one boosted playback backend failed')
  local expected=0.7*10^(6/20)
  expect(math.abs(tracked.sounds[1].settings.volume-expected)<1e-9 and math.abs(fallback.sounds[1].settings.volume-expected)<1e-9,'backends applied different gain')
  expect(tracked.api.status().lastBackend=='dynamic' and fallback.api.status().lastBackend=='ext','boost changed backend selection')
end)

local quoted={};for i,name in ipairs(checks)do quoted[i]='"'..name:gsub('\\','\\\\'):gsub('"','\\"')..'"'end
_TEST_CHECKS_JSON='['..table.concat(quoted,',')..']'
