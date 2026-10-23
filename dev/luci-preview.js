/* Development-only adapters. This executes the production view unchanged. */
'use strict';
(function() {
var packageName = 'airconnect-manager', count = 0;
var data = { main: { '.name': 'main', '.type': 'main', enabled: '1', interface: 'br-lan', airupnp: '1', aircast: '1', codec: 'flac', latency: '1000:2000', max_volume: '100', media_volume: '0.5', log_level: 'warn', metadata: '1', artwork: '', flush: '1', drift: '0', http_length: '-1', upnp_max: '1', stop_receiver: '0' },
  example: { '.name': 'example', '.type': 'device', engine: 'upnp', udn: 'uuid:example-speaker-001', enabled: '1', name: '' },
  example_cast: { '.name': 'example_cast', '.type': 'device', engine: 'cast', udn: 'uuid:example-cast-002', enabled: '1', name: '' } };
var saved = JSON.stringify(data), committed = saved;
// The four states are separate in the mock exactly as they are in the backend, so
// the page can be inspected in every combination without a router. The default is
// a completed observation in which the UPnP speaker is advertised and the
// Chromecast one is not; ?broadcast=unknown and ?broadcast=failed switch to the
// two ways the state can be unmeasured.
var observedAt = Math.floor(Date.now()/1000);
var broadcastMode = 'measured';
var status = { enabled: true, interface: 'br-lan', version: 'development',
  services: { upnp: {enabled:true,running:true,broadcasting:true}, cast:{enabled:true,running:true,broadcasting:false} },
  scan:{running:false,last_scan:observedAt},
  broadcast:{observed_at:observedAt,error:null},
  playback:{known:false,reason:'no documented engine status API'},
  conflicts:[], devices:[
  {engine:'upnp',udn:'uuid:example-speaker-001',original_name:'Example living room speaker',name:null,model:'Demo speaker',manufacturer:'Example manufacturer',address:'192.0.2.20',last_seen:observedAt,online:true,configured:true,broadcasting:true},
  {engine:'cast',udn:'uuid:example-cast-002',original_name:'Example study speaker',name:null,model:null,manufacturer:null,address:'192.0.2.21',last_seen:null,online:false,configured:true,broadcasting:false}
]};
var query = new URLSearchParams(location.search);
if(query.has('empty')){data={main:data.main};status.devices=[];saved=JSON.stringify(data);committed=saved;}
if(query.has('conflict')) status.conflicts=['Example legacy AirConnect process is active.'];
if(query.has('broadcast')){
  broadcastMode = query.get('broadcast');
  if(broadcastMode==='unknown'){
    // No completed observation at all: every broadcast value must be null.
    status.broadcast={observed_at:null,error:null};
    status.services.upnp.broadcasting=null; status.services.cast.broadcasting=null;
    status.devices.forEach(function(d){ d.broadcasting=null; });
  } else if(broadcastMode==='failed'){
    // The observation ran and could not be parsed: unknown, with a reason.
    status.broadcast={observed_at:observedAt,error:'no reply'};
    status.services.upnp.broadcasting=null; status.services.cast.broadcasting=null;
    status.devices.forEach(function(d){ d.broadcasting=null; });
  } else if(broadcastMode==='none'){
    // A completed scan that found nothing: false everywhere, which is a real
    // measurement and must render differently from unknown.
    status.services.upnp.broadcasting=false; status.services.cast.broadcasting=false;
    status.devices.forEach(function(d){ d.broadcasting=false; });
  }
}
function E(tag,attrs,children){if(attrs==null)attrs={};var node=document.createElement(tag);Object.keys(attrs).forEach(function(k){var v=attrs[k];if(typeof v==='function')node.addEventListener(k,v);else if(v===true)node.setAttribute(k,'');else if(v!==false&&v!=null)node.setAttribute(k,v);});function add(c){if(c==null)return;if(Array.isArray(c))c.forEach(add);else node.appendChild(c instanceof Node?c:document.createTextNode(String(c)));}add(children);return node;}
var uci={load:function(){return Promise.resolve();},get:function(c,s,k){return data[s]&&(k?data[s][k]:data[s]);},set:function(c,s,k,v){data[s][k]=v;},unset:function(c,s,k){delete data[s][k];},add:function(c,type){var id='demo'+(++count);data[id]={'.name':id,'.type':type};return id;},sections:function(c,type,fn){var sections=Object.values(data).filter(function(s){return s['.type']===type;});if(fn)sections.forEach(fn);return sections;},save:function(){saved=JSON.stringify(data);return Promise.resolve();}};
function Map(config){this.config=config;this.sections=[];}
Map.prototype.section=function(type,id,kind,title){var section={id:id,title:title,options:[],option:function(type,key,label,description){var o={type:type,key:key,label:label,description:description,values:[],value:function(v,l){this.values.push([v,l]);}};this.options.push(o);return o;}};this.sections.push(section);return section;};
Map.prototype.render=function(){var map=E('div',{'class':'cbi-map'});this.sections.forEach(function(s){var fieldset=E('fieldset',{'class':'cbi-section'});if(s.title)fieldset.appendChild(E('legend',{},s.title));s.options.forEach(function(o){var id='field-'+s.id+'-'+o.key, value=uci.get(packageName,s.id,o.key)||'',input;
if(o.type==='flag'){input=E('input',{type:'checkbox',id:id});input.checked=value==='1';}else if(o.type==='list'){input=E('select',{id:id});o.values.forEach(function(pair){input.appendChild(E('option',{value:pair[0]},pair[1]));});input.value=value;}else input=E('input',{type:'text',id:id,value:value,placeholder:o.placeholder});
o.input=input;var error=E('div',{'class':'demo-error',id:id+'-error',role:'alert'});o.error=error;input.setAttribute('aria-describedby',id+'-description '+id+'-error');var description=E('div',{'class':'cbi-value-description',id:id+'-description'},o.description||'');var row=E('div',{'class':'cbi-value'},[E('label',{'class':'cbi-value-title',for:id},o.label),E('div',{'class':'cbi-value-field'},[input,description,error])]);fieldset.appendChild(row);});map.appendChild(fieldset);});return Promise.resolve(map);};
Map.prototype.parse=function(){var errors=[];this.sections.forEach(function(s){s.options.forEach(function(o){var v=o.type==='flag'?(o.input.checked?'1':'0'):o.input.value;var valid=o.validate?o.validate(s.id,v):true;if(!v&&o.rmempty===false&&o.type!=='flag')valid='This field is required.';o.error.textContent=valid===true?'':String(valid);o.input.setAttribute('aria-invalid',valid===true?'false':'true');if(valid!==true)errors.push(valid);else if(v==='')uci.unset(packageName,s.id,o.key);else uci.set(packageName,s.id,o.key,v);});});return errors.length?Promise.reject(new Error(errors.join('\n'))):Promise.resolve();};
var calls={status:0,scan:0,logs:0,validate:0,action:0};
var rpc={declare:function(spec){return function(value){calls[spec.method]++;return new Promise(function(resolve,reject){setTimeout(function(){if(query.has('error')&&spec.method==='status')return reject(new Error('Demo RPC connection unavailable.'));switch(spec.method){case'status':return resolve(structuredClone(status));case'scan':status.scan.running=true;setTimeout(function(){status.scan.running=false;status.scan.last_scan=Math.floor(Date.now()/1000);},1800);return resolve({ok:true,running:true});case'logs':return resolve({lines:['[demo] manager started','[demo] UPnP discovery completed'],truncated:false});case'validate':return resolve(query.has('invalid')?{ok:false,errors:['Demo backend rejected configuration.']}:{ok:true,errors:[]});case'action':Object.values(status.services).forEach(function(s){s.running=s.enabled&&value!=='stop';});return resolve({ok:true});}},120);});};}};
var intervals=[];var poll={add:function(fn,seconds){intervals.push(setInterval(fn,seconds*1000));}};
var ui={addNotification:function(title,node){document.getElementById('notices').appendChild(node);},changes:{init:function(){return Promise.resolve();},apply:function(){committed=saved;status.interface=data.main.interface;status.enabled=data.main.enabled==='1';status.services.upnp.enabled=data.main.airupnp==='1';status.services.upnp.running=status.enabled&&status.services.upnp.enabled;status.services.cast.enabled=data.main.aircast==='1';status.services.cast.running=status.enabled&&status.services.cast.enabled;ui.addNotification(null,E('p',{},'Demo apply confirmed. No router settings changed.'));return Promise.resolve();}}};
var L={bind:function(fn,ctx){return fn.bind(ctx);},resource:function(path){return '/packages/luci-app-airconnect-manager/htdocs/luci-static/resources/'+path;}};
var translate=function(s){return s;};
function source(path){return fetch(path).then(function(r){return r.text();});}
// LuCI's loader resolves `'require airconnect-manager.rules as rules'`; here the
// same static resource is evaluated in a shim and passed in as an argument.
var rulesSource=source('/packages/luci-app-airconnect-manager/htdocs/luci-static/resources/airconnect-manager/rules.js');
var viewSource=source('/packages/luci-app-airconnect-manager/htdocs/luci-static/resources/view/airconnect-manager/overview.js');
Promise.all([rulesSource,viewSource]).then(function(sources){var rules=new Function('_','module',sources[0]+'\nreturn module.exports;')(translate,{exports:{}});
var instance=new Function('view','form','uci','rpc','ui','poll','L','E','_','rules',sources[1])({extend:function(o){return o;}},{Map:Map,NamedSection:'named',Flag:'flag',Value:'value',ListValue:'list'},uci,rpc,ui,poll,L,E,translate,rules);window.airconnectDemo={view:instance,uci:uci,status:status,calls:calls,data:data,rules:rules};return instance.load().then(function(r){return instance.render(r);}).then(function(node){document.getElementById('app').replaceChildren(node);['save','apply','reset'].forEach(function(id){document.getElementById(id).onclick=function(){var fn=id==='save'?'handleSave':id==='apply'?'handleSaveApply':'handleReset';Promise.resolve(instance[fn]()).catch(function(){});};});});}).catch(function(error){document.getElementById('app').textContent=error.stack;});
})();
