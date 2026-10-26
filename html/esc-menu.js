var $=function(s){return document.querySelector(s)},$$=function(s){return Array.prototype.slice.call(document.querySelectorAll(s))};

// Comunicação segura com a NUI principal. Este arquivo roda dentro do iframe
// do menu ESC, portanto não pode chamar GetParentResourceName() diretamente.
function sendParentNui(type, payload){
  if(window.parent && window.parent !== window){
    window.parent.postMessage(Object.assign({type:type}, payload || {}), '*');
  }
}
var ord=['home','corridas','online','customisation','crew','theatre'],cur='home';
var lockedViews={};
var mapConfirmOpen=false;
var garageConfirmOpen=false,garagePendingVehicle=null;
var garageCatalog={vehicles:[],brand:'TODOS',search:'',currentIndex:0,currentModel:'',currentVehicle:null,favoritesOnly:false};
var garageCatalogSignature=null,garageAwaitingData=false;
var garageImageSourceCache=Object.create(null),garageImageObserver=null;
var garagePreviewModel=null;
var garageFavorites=Object.create(null);
try{var savedGarageFavorites=JSON.parse(localStorage.getItem('apexnui:garage:favorites')||'[]');if(Array.isArray(savedGarageFavorites))savedGarageFavorites.forEach(function(model){garageFavorites[String(model).toLowerCase()]=true})}catch(_){}
function saveGarageFavorites(){try{localStorage.setItem('apexnui:garage:favorites',JSON.stringify(Object.keys(garageFavorites).filter(function(model){return garageFavorites[model]})))}catch(_){}}
function updateGarageFavoritesFilter(){var button=$('#garage-favorites-filter');if(button){button.classList.toggle('on',garageCatalog.favoritesOnly);button.setAttribute('aria-pressed',String(garageCatalog.favoritesOnly))}var count=$('#garage-favorites-count');if(count)count.textContent=String(garageCatalog.vehicles.filter(function(vehicle){return garageFavorites[String(vehicle.model||'').toLowerCase()]}).length)}
function handleConfirmationKey(e){
  if(!mapConfirmOpen&&!garageConfirmOpen)return false;
  var cancel=mapConfirmOpen?$('#mapConfirmNo'):$('#garageConfirmCancel');
  var accept=mapConfirmOpen?$('#mapConfirmYes'):$('#garageConfirmAccept');
  if(e.key==='Escape'||e.key==='Backspace'){
    e.preventDefault();e.stopPropagation();
    if(mapConfirmOpen)hideMapConfirmation();else hideGarageConfirmation();
    return true;
  }
  if(e.key==='ArrowLeft'||e.key==='ArrowRight'){
    e.preventDefault();e.stopPropagation();
    var target=e.key==='ArrowLeft'?cancel:accept;
    if(target)target.focus();
    return true;
  }
  if(e.key==='Enter'){
    e.preventDefault();e.stopPropagation();
    if(document.activeElement===cancel){if(mapConfirmOpen)hideMapConfirmation();else hideGarageConfirmation();}
    else if(mapConfirmOpen)confirmOpenMap();else confirmGarageVehicle();
    return true;
  }
  e.preventDefault();e.stopPropagation();
  return true;
}
function showMapConfirmation(){
  var modal=$('#mapConfirm');
  if(!modal)return;
  mapConfirmOpen=true;
  modal.classList.add('on');
  modal.setAttribute('aria-hidden','false');
  if(document.activeElement&&document.activeElement.blur)document.activeElement.blur();
}
function hideMapConfirmation(){
  var modal=$('#mapConfirm');
  if(!modal)return;
  mapConfirmOpen=false;
  modal.classList.remove('on');
  modal.setAttribute('aria-hidden','true');
  if(document.activeElement&&modal.contains(document.activeElement))document.activeElement.blur();
}
function confirmOpenMap(){
  hideMapConfirmation();
  if(window.parent && window.parent !== window){
    window.parent.postMessage({type:'apex-activate-esc-item', itemId:'map'}, '*');
  }
}
function showGarageConfirmation(vehicle){
  if(!vehicle)return;
  garagePendingVehicle=vehicle;
  var modal=$('#garageConfirm');
  if(!modal)return;
  $('#garageConfirmCurrent').textContent=garageCatalog.currentVehicle?String(garageCatalog.currentVehicle.displayName||garageCatalog.currentVehicle.model||'VEÍCULO ATUAL').toUpperCase():'A PÉ';
  $('#garageConfirmNext').textContent=String(vehicle.displayName||vehicle.model||'VEÍCULO').toUpperCase();
  garageConfirmOpen=true;
  modal.classList.add('on');
  modal.setAttribute('aria-hidden','false');
  if(document.activeElement&&document.activeElement.blur)document.activeElement.blur();
}
function hideGarageConfirmation(){
  var modal=$('#garageConfirm');
  garageConfirmOpen=false;
  garagePendingVehicle=null;
  if(!modal)return;
  modal.classList.remove('on');
  modal.setAttribute('aria-hidden','true');
  if(document.activeElement&&modal.contains(document.activeElement))document.activeElement.blur();
}
function confirmGarageVehicle(){
  if(!garagePendingVehicle)return;
  var vehicle=garagePendingVehicle;
  hideGarageConfirmation();
  sendParentNui('apex-spawn-garage-vehicle',{model:vehicle.model,handlingType:vehicle.handlingType||'light'});
}

function stepTab(dir){
  var currentTab=(cur==='config'||cur==='garage')?'home':cur;
  var i=ord.indexOf(currentTab),n=ord.length;
  for(var c=0;c<n;c++){
    i=(i+dir+n)%n;
    if(!lockedViews[ord[i]]){go(ord[i]);return}
  }
}

window.addEventListener('message',function(event){
  var data=event.data||{};
  if(data.type==='apex-esc-profile-summary'){
    var name=$('#menu-player-name');
    if(name)name.textContent=String(data.displayName||'PILOTO').toLocaleUpperCase('pt-BR');
    syncGaragePlayer();
  }
  if(data.type==='apex-economy-summary'){
    var economy=data.economy||{};
    var level=$('#menu-player-level');
    var money=$('#menu-player-money');
    if(level)level.textContent=String(Math.max(1,Math.floor(Number(economy.level)||1)));
    if(money)money.textContent='$ '+Math.max(0,Math.floor(Number(economy.balance)||0)).toLocaleString('pt-BR');
  }
});

$$('.tb').forEach(function(t){
  var v=t.dataset.v;
  if(lockedViews[v]){
    t.classList.add('lk');
    t.setAttribute('aria-disabled','true');
    t.setAttribute('title','Área bloqueada');
  }
  t.onclick=function(){
    if(lockedViews[v]){toast('Área bloqueada');return}
    go(v)
  }
});
$$('[data-go]').forEach(function(t){
  t.onclick=function(){go(t.dataset.go)}
});
var keyboardIndex=0;
function keyboardItems(){
  if(cur==='home') return $$('#v-home .home-dashboard > button');
  if(cur==='corridas'){
    if($('#creator-page').style.display!=='none')return $$('#creator-new-track:not(.permission-locked), #creator-track-grid .creator-track-card:not(.permission-locked), #creator-back');
    if($('#clist').style.display!=='none')return $$('#clist .tc, #clist [id="drc"], #clist [id="dfv"], #clist [id="ded"]:not(.permission-locked)');
    if($('#clist2').style.display!=='none')return $$('#clist2 .tc, #clist2 #abm, #clist2 #abg');
    return $$('#chub [data-k]:not(.permission-locked)');
  }
  if(cur==='online'){
    if($('#omm').style.display!=='none')return $$('#omm [data-b], #omm .vc, #omm #qbtn, #omm #mcb');
    if($('#ohi').style.display!=='none')return $$('#ohi [data-b]');
    return $$('#ohub [data-o]');
  }
  if(cur==='customisation')return $$('#v-customisation [data-home-action]:not([aria-disabled="true"])');
  if(cur==='garage') return $$('#garage-cards .garage-model-card');
  if(cur==='config') return $$('#cc .cs.on .row, #cc .cs.on .wx div[data-weather], #cc .cs.on .ps>div, #cc .cs.on .gt');
  if(cur==='admin') return $$('.sub2 div[data-a]');
  return [];
}
function updateKeyboardFocus(){
  var items=keyboardItems();
  var homeDashboard=$('#v-home .home-dashboard');
  if(homeDashboard)homeDashboard.classList.toggle('has-kb-selection',cur==='home'&&items.length>0);
  if(!items.length)return;
  if(keyboardIndex<0)keyboardIndex=items.length-1;
  if(keyboardIndex>=items.length)keyboardIndex=0;
  items.forEach(function(x,i){
    if(cur==='config')x.classList.toggle('config-selected',i===keyboardIndex);
    else x.classList.toggle('kb-focus',i===keyboardIndex);
  });
  if(cur==='garage'&&items[keyboardIndex])items[keyboardIndex].scrollIntoView({block:'nearest',inline:'center'});
  if(cur==='corridas'&&items[keyboardIndex]&&items[keyboardIndex].classList.contains('tc'))items[keyboardIndex].scrollIntoView({block:'nearest',inline:'nearest'});
  if(cur==='config'){
    var row=items[keyboardIndex],label=row&&row.querySelector(':scope > span:first-child');
    if(row)updateConfigDetail(activeConfigCategory,(label?label.innerText:row.innerText).trim().split('\n')[0]);
  }
}
function resetKeyboardFocus(){keyboardIndex=0;updateKeyboardFocus();var soloHub=$('#chub');if(soloHub)soloHub.classList.toggle('solo-keyboard-mode',cur==='corridas')}

var soloHub=$('#chub');
if(soloHub)soloHub.addEventListener('pointerover',function(event){
  var card=event.target.closest('[data-k]');
  if(!card||card.contains(event.relatedTarget))return;
  var items=keyboardItems(),index=items.indexOf(card);
  if(index<0)return;
  soloHub.classList.remove('solo-keyboard-mode');
  keyboardIndex=index;
  updateKeyboardFocus();
});

function go(v,fromParent){
  if(v==='mapa'){
    showMapConfirmation();
    return;
  }
  var previousView=cur;
  cur=v;
  if(previousView==='garage'&&v!=='garage'){garagePreviewModel=null;sendParentNui('apex-stop-garage-preview');}
  if(v==='garage'&&previousView!=='garage')garagePreviewModel=null;
  var ui=$('.ui');
  if(ui)ui.classList.toggle('garage-screen',v==='garage');
  if(ui)ui.classList.toggle('config-screen',v==='config');
  if(v==='garage'&&!fromParent)sendParentNui('apex-open-garage-catalog');
  if(v==='online')osw('ohub');
  if(v==='corridas'){$('#chub').style.display='';$('#clist').style.display='none';$('#clist2').style.display='none';$('#creator-page').style.display='none'}
  $$('.v').forEach(function(e){e.classList.toggle('on',e.id==='v-'+v)});
  $$('.tb').forEach(function(e){e.classList.toggle('on',e.dataset.v===((v==='config'||v==='garage')?'home':v))});
  $('.dim').style.opacity=(v==='mapa'||v==='garage')?.15:.75;
  resetKeyboardFocus();
}

$$('[data-home-action]').forEach(function(button){
  button.addEventListener('click',function(){
    var action=button.dataset.homeAction;
    if(button.getAttribute('aria-disabled')==='true'){
      toast('Este recurso chega em breve.');
      return;
    }
    if(action==='profile'){
      sendParentNui('apex-activate-esc-item',{itemId:'profile'});
    }else if(action==='free'){
      sendParentNui('apex-close-esc');
    }
  });
});

function activateKeyboardItem(){
  var items=keyboardItems();
  if(!items.length)return;
  var item=items[keyboardIndex];
  if(!item)return;
  if(cur==='config'&&item.matches('.row')){
    var toggle=item.querySelector('.tg'),select=item.querySelector('select'),range=item.querySelector('input[type="range"]');
    if(toggle){toggle.click();return}
    if(select){select.focus();select.click();return}
    if(range){range.focus();return}
    var selectedPill=item.querySelector('.pill.on');
    if(selectedPill){selectedPill.click();return}
  }
  item.click();
}

function moveKeyboard(dir){
  var items=keyboardItems();
  if(!items.length)return;
  keyboardIndex=(keyboardIndex+dir+items.length)%items.length;
  updateKeyboardFocus();
}

function moveHomeGrid(key){
  var items=keyboardItems();
  if(!items.length)return;
  var next=keyboardIndex;
  if(key==='ArrowLeft'){
    if(keyboardIndex===1)next=0;
    else if(keyboardIndex>=3&&keyboardIndex<=7)next--;
  }else if(key==='ArrowRight'){
    if(keyboardIndex===0)next=1;
    else if(keyboardIndex>=2&&keyboardIndex<7)next++;
  }else if(key==='ArrowUp'){
    if(keyboardIndex>=2)next=keyboardIndex<=4?0:1;
    else next=keyboardIndex===0?2:5;
  }else if(key==='ArrowDown'){
    if(keyboardIndex<2)next=keyboardIndex===0?2:5;
    else next=keyboardIndex<=4?0:1;
  }
  if(next===keyboardIndex)return;
  keyboardIndex=next;
  updateKeyboardFocus();
}

function moveSoloGrid(key){
  var items=keyboardItems();
  if(!items.length)return;
  var next=keyboardIndex;
  if(key==='ArrowLeft'){
    if(keyboardIndex>0)next=0;
  }else if(key==='ArrowRight'){
    if(keyboardIndex===0)next=1;
  }else if(key==='ArrowUp'){
    if(keyboardIndex===1)next=0;
    else if(keyboardIndex>1)next--;
  }else if(key==='ArrowDown'){
    if(keyboardIndex===0)next=1;
    else if(keyboardIndex<items.length-1)next++;
  }
  if(next===keyboardIndex)return;
  keyboardIndex=next;
  updateKeyboardFocus();
}

function moveGarageGrid(key){
  var items=keyboardItems();
  if(!items.length)return;
  var next=keyboardIndex;
  if(key==='ArrowLeft')next=keyboardIndex-1;
  else if(key==='ArrowRight')next=keyboardIndex+1;
  else if(key==='ArrowUp')next=keyboardIndex-GARAGE_COLS;
  else if(key==='ArrowDown'){
    next=keyboardIndex+GARAGE_COLS;
    // Última linha incompleta: vai para o último card em vez de ficar parado.
    if(next>=items.length&&Math.floor(keyboardIndex/GARAGE_COLS)<Math.floor((items.length-1)/GARAGE_COLS))next=items.length-1;
  }
  if(next<0||next>=items.length||next===keyboardIndex)return;
  keyboardIndex=next;
  updateKeyboardFocus();
  items[keyboardIndex].scrollIntoView({block:'nearest'});
  var focusedVehicle=garageCatalog.vehicles.find(function(vehicle){return String(vehicle.model||'').toLowerCase()===String(items[keyboardIndex].dataset.model||'').toLowerCase()});
  if(focusedVehicle)selectGaragePreview(focusedVehicle);
}

function moveTrackGrid(key){
  var items=keyboardItems(),cards=items.filter(function(item){return item.classList.contains('tc')}),current=items[keyboardIndex];
  if(!items.length||!cards.length)return;
  if(!current||!current.classList.contains('tc')){
    if(key==='ArrowUp'||key==='ArrowDown'){keyboardIndex=items.indexOf(cards.filter(function(card){return card.classList.contains('on')})[0]||cards[0]);updateKeyboardFocus();return}
    var actions=items.filter(function(item){return item.id==='abm'||item.id==='abg'||item.id==='drc'||item.id==='dfv'||item.id==='ded'});
    if(actions.length){var ai=actions.indexOf(current),step=key==='ArrowRight'?1:-1;keyboardIndex=items.indexOf(actions[(ai+step+actions.length)%actions.length]);updateKeyboardFocus()}
    return;
  }
  var grid=current.closest('.tgrid'),cols=getComputedStyle(grid).gridTemplateColumns.split(' ').length,index=cards.indexOf(current),next=index;
  if(key==='ArrowLeft')next=Math.max(0,index-1);
  else if(key==='ArrowRight')next=Math.min(cards.length-1,index+1);
  else if(key==='ArrowUp')next=Math.max(0,index-cols);
  else if(key==='ArrowDown')next=Math.min(cards.length-1,index+cols);
  if(next!==index){keyboardIndex=items.indexOf(cards[next]);updateKeyboardFocus();var chosen=cards[next],trackIndex=+chosen.dataset.i;if(grid&&grid.id==='tg'){ts=trackIndex;cards.forEach(function(card){card.classList.toggle('on',+card.dataset.i===ts)});tdet()}else if(grid&&grid.id==='tg2'){ts2=trackIndex;cards.forEach(function(card){card.classList.toggle('on',+card.dataset.i===ts2)});ab2()}return}
  if(key==='ArrowDown'&&index===cards.length-1){var firstAction=items.find(function(item){return item.id==='abm'||item.id==='drc'});if(firstAction){keyboardIndex=items.indexOf(firstAction);updateKeyboardFocus()}}
}

function stepConfigCategory(dir){
  var tabs=$$('.cfg-tabs div[data-c]');
  if(!tabs.length)return;
  var active=$('.cfg-tabs div[data-c].on'),index=tabs.indexOf(active);
  tabs[(index+dir+tabs.length)%tabs.length].click();
}

function adjustConfigOption(dir){
  var item=keyboardItems()[keyboardIndex];
  if(!item)return;
  if(item.matches('.wx div[data-weather]')){
    var weather=weatherButtons(),index=weather.indexOf(item);
    weather[(index+dir+weather.length)%weather.length].click();
    return;
  }
  if(item.matches('.ps>div')){
    var presets=$$('#c-perf .ps>div'),index=presets.indexOf(item);
    presets[(index+dir+presets.length)%presets.length].click();
    return;
  }
  var toggle=item.querySelector('.tg');
  if(toggle){toggle.click();return}
  var select=item.querySelector('select');
  if(select&&select.options.length){
    select.selectedIndex=(select.selectedIndex+dir+select.options.length)%select.options.length;
    select.dispatchEvent(new Event('change',{bubbles:true}));
    return;
  }
  var pills=Array.prototype.filter.call(item.querySelectorAll('.pill'),function(p){return p.parentNode===item||p.parentNode.parentNode===item});
  if(pills.length){
    var active=pills.findIndex(function(p){return p.classList.contains('on')});
    pills[(active+dir+pills.length)%pills.length].click();
    return;
  }
  var range=item.querySelector('input[type="range"]');
  if(range&&!range.disabled){
    var step=Number(range.step)||1,min=Number(range.min)||0,max=Number(range.max)||100;
    range.value=Math.max(min,Math.min(max,Number(range.value)+step*dir));
    range.dispatchEvent(new Event('input',{bubbles:true}));
  }
}

document.onkeydown=function(e){
  if(handleConfirmationKey(e))return;
  if(cur==='garage'){
    if(e.target===$('#garage-search')){
      if(e.key==='Escape'){e.preventDefault();e.stopPropagation();go('home')}
      return;
    }
    if(e.key==='Escape'||e.key==='Backspace') {e.preventDefault();e.stopPropagation();go('home');return;}
    if(e.key==='ArrowDown'||e.key==='ArrowUp'||e.key==='ArrowLeft'||e.key==='ArrowRight') {e.preventDefault();e.stopPropagation();moveGarageGrid(e.key);return;}
    if(e.key.toLowerCase()==='q'||e.key.toLowerCase()==='r') {e.preventDefault();e.stopPropagation();stepGarageBrand(e.key.toLowerCase()==='r'?1:-1);return;}
    if(e.key.toLowerCase()==='f'){e.preventDefault();e.stopPropagation();var focusedGarageCard=keyboardItems()[keyboardIndex];if(focusedGarageCard)toggleGarageFavorite(focusedGarageCard.dataset.model);return;}
    if(e.key==='Enter') {e.preventDefault();e.stopPropagation();activateKeyboardItem();return;}
    return;
  }
  if(e.key==='Escape'){
    e.preventDefault();e.stopPropagation();
    if(cur==='config'){go('home');return;}
    if(window.parent!==window)window.parent.postMessage({type:'apex-close-esc'},'*');
    return;
  }
  if(cur==='config'&&e.key==='Backspace'){
    e.preventDefault();e.stopPropagation();go('home');return;
  }
  if(cur==='config'&&e.key==='Delete'){
    e.preventDefault();e.stopPropagation();$('#gtShortcut').click();return;
  }
  // Q/R percorrem as categorias de configurações; fora dela, Q/E trocam a aba principal.
  if(cur==='config'&&(e.key==='q'||e.key==='Q')){
    e.preventDefault();e.stopPropagation();stepConfigCategory(-1);return;
  }
  if(cur==='config'&&(e.key==='r'||e.key==='R')){
    e.preventDefault();e.stopPropagation();stepConfigCategory(1);return;
  }
  if(e.key==='e'||e.key==='E'){
    e.preventDefault();e.stopPropagation();stepTab(1);return;
  }
  if(e.key==='q'||e.key==='Q'){
    e.preventDefault();e.stopPropagation();stepTab(-1);return;
  }
  if(cur==='home'&&['ArrowDown','ArrowUp','ArrowLeft','ArrowRight'].indexOf(e.key)!==-1){
    e.preventDefault();e.stopPropagation();moveHomeGrid(e.key);return;
  }
  if(cur==='corridas'&&$('#chub').style.display!=='none'&&['ArrowDown','ArrowUp','ArrowLeft','ArrowRight'].indexOf(e.key)!==-1){
    e.preventDefault();e.stopPropagation();
    $('#chub').classList.add('solo-keyboard-mode');
    moveSoloGrid(e.key);return;
  }
  if(cur==='corridas'&&($('#clist').style.display!=='none'||$('#clist2').style.display!=='none')&&['ArrowDown','ArrowUp','ArrowLeft','ArrowRight'].indexOf(e.key)!==-1){
    e.preventDefault();e.stopPropagation();moveTrackGrid(e.key);return;
  }
  if(cur==='corridas'&&$('#creator-page').style.display!=='none'&&['ArrowDown','ArrowUp','ArrowLeft','ArrowRight'].indexOf(e.key)!==-1){
    e.preventDefault();e.stopPropagation();moveKeyboard(e.key==='ArrowLeft'||e.key==='ArrowUp'?-1:1);return;
  }
  // Setas navegam dentro do submenu da aba atual.
  if(e.key==='ArrowDown'){
    e.preventDefault();e.stopPropagation();moveKeyboard(1);return;
  }
  if(e.key==='ArrowUp'){
    e.preventDefault();e.stopPropagation();moveKeyboard(-1);return;
  }
  if(cur==='config'&&(e.key==='ArrowLeft'||e.key==='ArrowRight')){
    e.preventDefault();e.stopPropagation();adjustConfigOption(e.key==='ArrowRight'?1:-1);return;
  }
  // Enter seleciona o item atualmente destacado.
  if(e.key==='Enter'){
    e.preventDefault();e.stopPropagation();activateKeyboardItem();return;
  }
};

function garageEscape(value){return String(value==null?'':value).replace(/[&<>"']/g,function(ch){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]})}
function garageBrand(vehicle){
  if(vehicle&&(vehicle.brand||vehicle.make))return String(vehicle.brand||vehicle.make).toUpperCase();
  return 'APEX';
}
function garageBrands(){return ['TODOS'].concat(Array.from(new Set(garageCatalog.vehicles.map(garageBrand))))}
function resolveGarageImageSource(model){
  var spawn=String(model||'').trim().toLowerCase();
  if(garageImageSourceCache[spawn])return garageImageSourceCache[spawn];
  var sources=[];
  if(/^[a-z0-9_-]+$/.test(spawn))['webp','png','jpg','jpeg','svg'].forEach(function(extension){sources.push('garage-images/'+spawn+'.'+extension)});
  sources.push('garage-images/vehicle-placeholder.svg');
  function trySource(index){
    if(index>=sources.length)return Promise.resolve('garage-images/vehicle-placeholder.svg');
    var source=sources[index];
    return new Promise(function(resolve){
      var image=new Image();
      image.onload=function(){
        if(typeof image.decode==='function')image.decode().then(function(){resolve(source)}).catch(function(){resolve(source)});
        else resolve(source);
      };
      image.onerror=function(){trySource(index+1).then(resolve)};
      image.src=source;
    });
  }
  garageImageSourceCache[spawn]=trySource(0);
  return garageImageSourceCache[spawn];
}
function resolveMultiplayerVehicleImage(model,preferred){
  if(!preferred)return resolveGarageImageSource(model);
  return new Promise(function(resolve){
    var probe=new Image();
    probe.onload=function(){resolve(preferred)};
    probe.onerror=function(){resolveGarageImageSource(model).then(resolve)};
    probe.src=preferred;
  });
}
function loadGarageCardImage(img){
  if(!img||img.dataset.loading==='true'||img.dataset.loaded==='true')return;
  img.dataset.loading='true';
  resolveGarageImageSource(img.dataset.spawn).then(function(source){
    if(!img.isConnected)return;
    img.onload=function(){img.dataset.loaded='true';img.dataset.loading='false';img.classList.add('is-loaded')};
    img.onerror=function(){img.dataset.loading='false';img.classList.add('is-loaded')};
    img.classList.toggle('is-placeholder',/vehicle-placeholder\.svg$/.test(source));
    img.src=source;
    if(img.complete&&img.naturalWidth>0){img.dataset.loaded='true';img.dataset.loading='false';img.classList.add('is-loaded')}
  });
}
function hydrateGarageCardImages(){
  if(garageImageObserver){garageImageObserver.disconnect();garageImageObserver=null}
  var images=Array.from($('#garage-cards').querySelectorAll('img[data-spawn]'));
  images.slice(0,8).forEach(loadGarageCardImage);
  if(typeof IntersectionObserver==='function'){
    garageImageObserver=new IntersectionObserver(function(entries){entries.forEach(function(entry){if(entry.isIntersecting){loadGarageCardImage(entry.target);garageImageObserver.unobserve(entry.target)}})},{root:$('.garage-grid-wrap'),rootMargin:'160px'});
    images.slice(8).forEach(function(img){garageImageObserver.observe(img)});
  }else images.slice(8).forEach(loadGarageCardImage);
}
function garageFilteredVehicles(){
  var search=garageCatalog.search.trim().toLowerCase();
  return garageCatalog.vehicles.filter(function(vehicle){
    if(garageCatalog.brand!=='TODOS'&&garageBrand(vehicle)!==garageCatalog.brand)return false;
    if(garageCatalog.favoritesOnly&&!garageFavorites[String(vehicle.model||'').toLowerCase()])return false;
    return !search||[vehicle.displayName,vehicle.model,garageBrand(vehicle),vehicle.classLabel].join(' ').toLowerCase().indexOf(search)>=0;
  });
}
function garageImageMarkup(vehicle){
  var spawn=String(vehicle&&vehicle.model||'').trim().toLowerCase();
  return '<img src="garage-images/vehicle-placeholder.svg" data-spawn="'+garageEscape(spawn)+'" alt="'+garageEscape(vehicle.displayName||vehicle.model)+'">';
}
function garageCurrentLabel(){
  var current=garageCatalog.currentVehicle;
  if(!current)return 'A PÉ';
  var model=String(current.model||'').toLowerCase();
  var entry=garageCatalog.vehicles.find(function(vehicle){return String(vehicle.model||'').toLowerCase()===model});
  var name=String(current.displayName||current.model||'VEÍCULO ATUAL');
  var brand=entry?garageBrand(entry):'';
  if(brand&&name.toUpperCase().indexOf(brand)!==0)name=brand+' '+name;
  return name.toUpperCase();
}
function syncGaragePlayer(){
  var source=$('#menu-player-name'),target=$('#garage-player-name');
  if(source&&target)target.textContent=source.textContent||'PILOTO';
  var label=$('#garage-current-car');
  if(label)label.textContent=garageCurrentLabel();
}
function selectGaragePreview(vehicle){
  if(!vehicle)return;
  garagePreviewModel=String(vehicle.model||'');
}
function toggleGarageFavorite(model){var key=String(model||'').toLowerCase();if(!key)return;if(garageFavorites[key])delete garageFavorites[key];else garageFavorites[key]=true;saveGarageFavorites();renderGarageCatalog()}
var GARAGE_COLS=4,GARAGE_MIN_SLOTS=12;
function garageEmptyCells(count){var html='';for(var i=0;i<count;i++)html+='<div class="garage-empty-cell"></div>';return html}
function renderGarageCatalog(){
  var tabs=$('#garage-brand-tabs'),cards=$('#garage-cards');
  if(!tabs||!cards)return;
  var brands=garageBrands();
  if(brands.indexOf(garageCatalog.brand)<0)garageCatalog.brand='TODOS';
  tabs.innerHTML=brands.map(function(brand){return '<button type="button" class="'+(brand===garageCatalog.brand?'on':'')+'" data-brand="'+garageEscape(brand)+'">'+garageEscape(brand==='TODOS'?'TODOS':brand)+'</button>'}).join('');
  var activeBrand=tabs.querySelector('.on');
  if(activeBrand)activeBrand.scrollIntoView({block:'nearest',inline:'center'});
  var vehicles=garageFilteredVehicles().slice();
  // O veículo atual fica sempre no primeiro card.
  var currentModel=garageCatalog.currentModel;
  if(currentModel){
    var currentAt=vehicles.findIndex(function(vehicle){return String(vehicle.model||'').toLowerCase()===currentModel});
    if(currentAt>0)vehicles.unshift(vehicles.splice(currentAt,1)[0]);
  }
  $('#garage-count').textContent=String(garageCatalog.vehicles.length);
  syncGaragePlayer();
  updateGarageFavoritesFilter();
  var slots=Math.max(GARAGE_MIN_SLOTS,Math.ceil(vehicles.length/GARAGE_COLS)*GARAGE_COLS);
  cards.classList.toggle('is-empty',vehicles.length===0);
  if(!vehicles.length){
    var message=garageCatalog.favoritesOnly?'NENHUM FAVORITO AINDA — USE F PARA FAVORITAR UM VEÍCULO':(garageCatalog.vehicles.length?'NENHUM VEÍCULO ENCONTRADO':'CARREGANDO CATÁLOGO DE VEÍCULOS...');
    cards.innerHTML=garageEmptyCells(GARAGE_MIN_SLOTS)+'<div class="garage-empty">'+message+'</div>';
    garagePreviewModel=null;
    return;
  }
  cards.innerHTML=vehicles.map(function(vehicle,index){
    var model=String(vehicle.model||'').toLowerCase(),current=model===currentModel,favorite=!!garageFavorites[model];
    return '<article class="garage-model-card'+(current?' selected':'')+'" data-index="'+index+'" data-model="'+garageEscape(vehicle.model)+'" data-handling="'+garageEscape(vehicle.handlingType||'light')+'">'
      +'<span class="garage-brand-tag">'+garageEscape(garageBrand(vehicle))+'</span>'
      +garageImageMarkup(vehicle)
      +'<h3>'+garageEscape(vehicle.displayName||vehicle.model)+'</h3>'
      +(current?'<span class="garage-current-tag">ATUAL</span>':'')
      +'<button class="garage-favorite-toggle'+(favorite?' on':'')+'" type="button" aria-label="'+(favorite?'Remover dos favoritos':'Adicionar aos favoritos')+'" aria-pressed="'+String(favorite)+'" title="'+(favorite?'Remover dos favoritos':'Adicionar aos favoritos')+'"><svg class="i"><use href="#star"/></svg></button>'
      +'</article>';
  }).join('')+garageEmptyCells(slots-vehicles.length);
  var wrap=$('#garage-grid-wrap');if(wrap)wrap.scrollTop=0;
  hydrateGarageCardImages();
  keyboardIndex=Math.max(0,Math.min(keyboardIndex,vehicles.length-1));
  updateKeyboardFocus();
  if(vehicles[keyboardIndex])selectGaragePreview(vehicles[keyboardIndex]);
}
function stepGarageBrand(direction){
  var brands=garageBrands();if(!brands.length)return;
  var index=brands.indexOf(garageCatalog.brand);if(index<0)index=0;
  garageCatalog.brand=brands[(index+direction+brands.length)%brands.length];
  keyboardIndex=0;renderGarageCatalog();
}
function requestGarageVehicle(card){
  if(!card)return;
  var vehicle=garageCatalog.vehicles.find(function(item){return String(item.model||'').toLowerCase()===String(card.dataset.model||'').toLowerCase()});
  if(!vehicle)return;
  selectGaragePreview(vehicle);
  showGarageConfirmation({model:vehicle.model,displayName:vehicle.displayName||vehicle.model,handlingType:card.dataset.handling||vehicle.handlingType||'light'});
}
$('#garage-cards').addEventListener('click',function(event){var favorite=event.target.closest('.garage-favorite-toggle');if(favorite){event.preventDefault();event.stopPropagation();toggleGarageFavorite(favorite.closest('.garage-model-card').dataset.model);return}requestGarageVehicle(event.target.closest('.garage-model-card'))});
$('#garage-cards').addEventListener('pointerover',function(event){var card=event.target.closest('.garage-model-card');if(!card||card.contains(event.relatedTarget))return;var vehicle=garageCatalog.vehicles.find(function(item){return String(item.model||'').toLowerCase()===String(card.dataset.model||'').toLowerCase()});if(!vehicle)return;keyboardIndex=Number(card.dataset.index)||0;updateKeyboardFocus();selectGaragePreview(vehicle)});
$('#garage-brand-tabs').addEventListener('click',function(event){var tab=event.target.closest('[data-brand]');if(!tab)return;garageCatalog.brand=tab.dataset.brand;keyboardIndex=0;renderGarageCatalog()});
if($('#garage-all'))$('#garage-all').onclick=function(){garageCatalog.brand='TODOS';garageCatalog.search='';garageCatalog.favoritesOnly=false;$('#garage-search').value='';renderGarageCatalog()};
$('#garage-favorites-filter').onclick=function(){garageCatalog.favoritesOnly=!garageCatalog.favoritesOnly;keyboardIndex=0;renderGarageCatalog()};
$('#garage-search').addEventListener('input',function(){garageCatalog.search=this.value||'';keyboardIndex=0;renderGarageCatalog()});
$('#garage-back').onclick=function(){if(multiplayerPickerReturn){multiplayerPickerReturn=false;go('online',true);osw('omm')}else go('home')};
$('#garage-close').onclick=function(){if(multiplayerPickerReturn){multiplayerPickerReturn=false;go('online',true);osw('omm')}else sendParentNui('apex-close-esc')};
$('#garage-close-footer').onclick=function(){if(multiplayerPickerReturn){multiplayerPickerReturn=false;go('online',true);osw('omm')}else sendParentNui('apex-close-esc')};
window.addEventListener('message',function(event){
  var data=event.data||{};
  if(data.type==='apex-garage-preview-status'){
    var stage=$('.garage-showcase'),status=$('#garage-preview-status');
    if(stage)stage.classList.toggle('preview-fallback',data.active!==true);
    if(status)status.textContent=data.message||(data.active?'PRÉVIA AO VIVO':'PRÉVIA INDISPONÍVEL — MOSTRANDO IMAGEM');
    if(data.active!==true&&String(data.message||'').indexOf('INDISPONÍVEL')>=0&&String(data.model||'')===garagePreviewModel)garagePreviewModel=null;
    return;
  }
  if(data.type==='apex-garage-open'){garageAwaitingData=true;garageCatalog.search='';$('#garage-search').value='';go('garage',true);$('#garage-cards').innerHTML='<div class="garage-empty">Carregando catálogo de veículos...</div>';return;}
  if(data.type==='apex-esc-closed'){hideGarageConfirmation();if(cur==='garage')go('home',true);return;}
  if(data.type==='apex-garage-data'){
    var payload=data.payload||{},signature;
    try{signature=JSON.stringify(payload)}catch(_){signature=''}
    if(!garageAwaitingData&&signature&&signature===garageCatalogSignature)return;
    garageCatalogSignature=signature;garageAwaitingData=false;
    garageCatalog.vehicles=Array.isArray(payload.vehicles)?payload.vehicles:[];garageCatalog.brand='TODOS';garageCatalog.search='';
    var current=payload.currentVehicle||null;garageCatalog.currentVehicle=current;garageCatalog.currentModel=current?String(current.model||'').toLowerCase():'';syncGaragePlayer();
    if(!garageCatalog.vehicles.length){renderGarageCatalog();return;}
    keyboardIndex=0; // o veículo atual é fixado no primeiro card
    renderGarageCatalog();
    return;
  }
});

resetKeyboardFocus();

var mapYes=$('#mapConfirmYes');
var mapNo=$('#mapConfirmNo');
if(mapYes)mapYes.onclick=confirmOpenMap;
if(mapNo)mapNo.onclick=hideMapConfirmation;
var garageConfirmCancel=$('#garageConfirmCancel'),garageConfirmAccept=$('#garageConfirmAccept'),garageConfirmModal=$('#garageConfirm');
if(garageConfirmCancel)garageConfirmCancel.onclick=hideGarageConfirmation;
if(garageConfirmAccept)garageConfirmAccept.onclick=confirmGarageVehicle;
if(garageConfirmModal)garageConfirmModal.addEventListener('click',function(event){if(event.target===garageConfirmModal)hideGarageConfirmation()});

var configCategoryInfo={
  gen:{label:'GERAL',title:'PREFERÊNCIAS GERAIS',text:'Configure preferências gerais e o ambiente visual aplicado somente para você.'},
  int:{label:'INTERFACE',title:'ELEMENTOS DA INTERFACE',text:'Personalize os controles, o velocímetro e os elementos exibidos na tela.'},
  cor:{label:'CORRIDA',title:'PREFERÊNCIAS DE CORRIDA',text:'Configure os elementos visuais e a unidade usada nas corridas.'},
};
var configOptionHelp={
  'Idioma':'Define o idioma dos textos e informações do menu.',
  'Modo de desempenho':'Ativa ou desativa as opções de desempenho do servidor.',
  'Compartilhar detalhes da atividade':'Controla o compartilhamento dos detalhes das suas atividades.',
  'Horário local':'Muda o horário que você vê no jogo; a alteração vale somente para o seu jogador.',
  'Restaurar ambiente do servidor':'Remove seu horário e clima personalizados e volta a acompanhar o ambiente do servidor.',
  'Botões do controle':'Escolha os ícones de botão mostrados para o seu controle.',
  'Unidade de velocidade':'Escolha entre quilômetros por hora e milhas por hora.',
  'Modelo do velocímetro':'Selecione o visual do velocímetro.',
  'Formato do minimapa':'Escolha entre o minimapa circular ou quadrado.',
  'Desfoque do minimapa':'Ativa ou desativa o efeito de desfoque do minimapa.',
  'Mostrar minimapa':'Exibe ou oculta o minimapa durante o jogo.',
  'Mostrar driver tags (nome e foto dos pilotos)':'Exibe ou oculta os nomes e as fotos dos pilotos.',
  'Volume da interface':'Ajuste o volume dos sons da interface.',
  'Linha de corrida':'Escolha como a linha de corrida aparece no percurso.',
  'Delta de checkpoint':'Escolha como o delta de tempo aparece ao passar por checkpoints.',
  'Checkpoints à frente':'Defina quantos checkpoints futuros ficam visíveis.',
  'Cor dos checkpoints':'Escolha a cor usada nos checkpoints.',
  'Som de checkpoint':'Ativa ou desativa o aviso sonoro de checkpoint.',
  'Correr contra o ghost':'Ativa ou desativa a corrida contra o seu ghost.'
};
var activeConfigCategory='gen';
function updateConfigDetail(category,selection){
  activeConfigCategory=category||activeConfigCategory;
  var info=configCategoryInfo[activeConfigCategory]||configCategoryInfo.gen;
  var kicker=$('#configDetailKicker'),title=$('#configDetailTitle'),text=$('#configDetailText');
  var selected=$('#configDetailSelection'),hint=$('#configDetailHint');
  if(kicker)kicker.textContent=info.label;
  if(title)title.textContent=selection?selection.toUpperCase():info.title;
  if(text)text.textContent=selection?(configOptionHelp[selection]||('Ajuste a opção “'+selection+'” usando o controle à esquerda.')):info.text;
  if(selected)selected.textContent=selection||info.title;
  if(hint)hint.textContent=selection?'Ative, desative ou ajuste esta opção no painel à esquerda.':'Selecione uma opção para ver mais detalhes.';
}
$$('.cfg-tabs div[data-c]').forEach(function(s){s.onclick=function(){
  $$('.cfg-tabs div[data-c]').forEach(function(x){x.classList.toggle('on',x===s)});
  $$('.cs').forEach(function(c){c.classList.toggle('on',c.id==='c-'+s.dataset.c)});
  $$('#cc .config-selected').forEach(function(x){x.classList.remove('config-selected')});
  updateConfigDetail(s.dataset.c,null);
  keyboardIndex=0;
  updateKeyboardFocus();
}});
$$('#cc .cs .row').forEach(function(row){row.onclick=function(){
  var label=row.querySelector(':scope > span:first-child');
  var selection=(label?label.innerText:row.innerText).trim().split('\n')[0];
  var section=row.closest('.cs');
  if(section){
    section.querySelectorAll('.row.config-selected').forEach(function(x){x.classList.remove('config-selected')});
    row.classList.add('config-selected');
  }
  updateConfigDetail(activeConfigCategory,selection);
}});
$('#gtShortcut').onclick=function(){
  sendParentNui('apex-activate-esc-item',{itemId:'settings'});
};
updateConfigDetail('gen',null);
$$('.tg').forEach(function(t){t.onclick=function(){t.classList.toggle('on');if(t.dataset.t)$('#'+t.dataset.t).style.display=t.classList.contains('on')?'':'none'}});
var WEATHER_OPTIONS=['clear','cloudy','rain','storm','fog','snow'];
var WEATHER_LABELS={clear:'Limpo',cloudy:'Nublado',rain:'Chuva',storm:'Tempestade',fog:'Neblina',snow:'Neve'};
var envLocked=false;
var envLock=$('#envLock');
var weatherButtons=function(){return $$('#player-weather div[data-weather]')};
function setEnvironmentLocked(locked){
  envLocked=locked===true;
}
function updateEnvironmentPreview(weather,hour){
  var panel=$('#envPreview');
  if(!panel)return;
  var selectedWeather=weather||((panel&&panel.dataset.weather)||'clear');
  var id=WEATHER_OPTIONS.indexOf(selectedWeather);
  if(id<0)id=0;
  var key=WEATHER_OPTIONS[id];
  var h=Math.max(0,Math.min(23,Number(hour)||0));
  var period=h<6?'night':(h<8?'dawn':(h<17?'day':(h<20?'evening':'night')));
  var periods={night:'Noite',dawn:'Amanhecer',day:'Dia',evening:'Entardecer'};
  var conditions={clear:'Visibilidade normal',cloudy:'Céu parcialmente nublado',rain:'Pista molhada',storm:'Tempestade ativa',fog:'Visibilidade reduzida',snow:'Condições de neve'};
  var icons={clear:'#sun',cloudy:'#cloud',rain:'#rain',storm:'#storm',fog:'#fog',snow:'#snow'};
  panel.dataset.weather=key;
  panel.dataset.period=period;
  var use=panel.querySelector('#envPreviewIcon use');
  if(use)use.setAttribute('href',icons[key]||'#sun');
  var weatherLabel=$('#envPreviewWeather');
  if(weatherLabel)weatherLabel.textContent=WEATHER_LABELS[key]||'Limpo';
  var timeLabel=$('#envPreviewTime');
  if(timeLabel)timeLabel.textContent=(h<10?'0':'')+h+':00';
  var periodLabel=$('#envPreviewPeriod');
  if(periodLabel)periodLabel.textContent=periods[period]||'Dia';
  var conditionLabel=$('#envPreviewCondition');
  if(conditionLabel)conditionLabel.textContent=conditions[key]||'Visibilidade normal';
}
function setWeatherVisual(weather, notifyParent){
  var id=WEATHER_OPTIONS.indexOf(weather);
  if(id<0)id=0;
  var key=WEATHER_OPTIONS[id];
  weatherButtons().forEach(function(x){x.classList.toggle('on',x.dataset.weather===key)});
  var label=$('#weatherLabel');
  if(label)label.textContent=WEATHER_LABELS[key]||'Limpo';
  var hsNow=$('#hs');
  updateEnvironmentPreview(key,hsNow?+hsNow.value:18);
  if(notifyParent){
    sendParentNui('apex-set-environment-weather',{weather:key});
  }
}
weatherButtons().forEach(function(w){
  w.onclick=function(){
    setWeatherVisual(w.dataset.weather,true);
  };
});
function minToHM(total){total=Math.max(0,Math.min(1439,Math.round(+total||0)));return {h:Math.floor(total/60),m:total%60}}
function hm(h,m){return String(h).padStart(2,'0')+':'+String(m).padStart(2,'0')}
var hs=$('#hs');
if(hs)hs.oninput=function(e){
  var t=minToHM(e.target.value);
  var hr=$('#hr');
  if(hr)hr.textContent=hm(t.h,t.m);
  updateEnvironmentPreview(null,t.h);
  sendParentNui('apex-set-environment-time',{hour:t.h,minute:t.m});
};
if(envLock){
  envLock.onclick=function(){
    setEnvironmentLocked(!envLocked);
    sendParentNui('apex-set-environment-lock',{enabled:envLocked});
  };
}
var envReset=$('#envReset');
if(envReset)envReset.onclick=function(){sendParentNui('apex-reset-environment')};
window.addEventListener('message',function(event){
  var data=event.data||{};
  if(data.type==='apex-environment-state' && data.environment){
    var env=data.environment;
    var hour=Number(env.time); if(!Number.isFinite(hour))hour=18;
    var minute=Number(env.minute); if(!Number.isFinite(minute))minute=0;
    // Enquanto o usuario esta arrastando o slider, nao sobrescreve o valor dele.
    if($('#hs')&&document.activeElement!==$('#hs'))$('#hs').value=hour*60+minute;
    if($('#hr'))$('#hr').textContent=hm(hour,minute);
    updateEnvironmentPreview(env.weatherId||'clear',hour);
    setWeatherVisual(env.weatherId||'clear',false);
    setEnvironmentLocked(env.locked===true);
  }
});
updateEnvironmentPreview('clear',18);

var P=[[[40,20,25,10],120],[[65,60,60,55],90],[[100,100,100,100],60]],L=['Renderização','Sombras','Props','Efeitos'];
function pf(k){$$('.ps>div').forEach(function(x){x.classList.toggle('on',+x.dataset.p===k)});var pb=document.getElementById('pb');if(pb){pb.innerHTML=P[k][0].map(function(v,i){return '<div class="sb"><span>'+L[i]+'</span><i><b style="width:'+v+'%"></b></i></div>'}).join('')}}
$$('.ps>div').forEach(function(x){x.onclick=function(){pf(+x.dataset.p)}});pf(1);
$$('.sv input').forEach(function(r){if(r.id==='hs')return;r.oninput=function(){r.previousSibling.textContent=r.value+r.dataset.f}});
$$('.pill').forEach(function(p){p.onclick=function(){
  Array.prototype.slice.call(p.parentNode.children).forEach(function(x){x.classList.toggle('on',x===p)});
  var row=p.closest('.row'),label=row&&row.querySelector(':scope > span:first-child');
  if(!row||!label||!row.closest('#c-int'))return;
  var setting=label.innerText.trim(),value=p.innerText.trim();
  if(setting==='Unidade de velocidade')sendParentNui('apex-set-hud-option',{option:'speedUnit',value:value==='MPH'?'mph':'kmh'});
  if(setting==='Modelo do velocímetro')sendParentNui('apex-set-hud-option',{option:'speedometerType',value:value==='Lâminas'?'svg':'apexnui'});
}});
window.addEventListener('message',function(event){
  var data=event.data||{},settings=data.settings||{};
  if(data.type!=='apex-hud-settings')return;
  var unitRow=$$('#c-int .row').find(function(row){return row.querySelector(':scope > span:first-child').innerText.trim()==='Unidade de velocidade'});
  var modelRow=$$('#c-int .row').find(function(row){return row.querySelector(':scope > span:first-child').innerText.trim()==='Modelo do velocímetro'});
  if(unitRow)unitRow.querySelectorAll('.pill').forEach(function(p){p.classList.toggle('on',p.innerText.trim()===(settings.speedUnit==='mph'?'MPH':'KM/H'))});
  if(modelRow)modelRow.querySelectorAll('.pill').forEach(function(p){p.classList.toggle('on',p.innerText.trim()===(settings.speedometerType==='svg'?'Lâminas':'Digital'))});
});
var wk=null;$$('.kc').forEach(function(k){k.onclick=function(){if(wk)wk.classList.remove('w');wk=k;k.dataset.o=k.textContent;k.textContent='Pressione…';k.classList.add('w')}});
window.addEventListener('keydown',function(e){if(wk){e.preventDefault();e.stopImmediatePropagation();wk.textContent=e.key.length>1?e.key.toUpperCase():e.key.toUpperCase();wk.classList.remove('w');wk=null}},true);
$('#gt').onclick=function(){$('#gn').textContent='Abrindo o menu do GTA… (no jogo, este menu fecha)';$('#gn').style.color='var(--ac)'};
$('#al').innerHTML=['Nitro','Vortex','Kaze','Drift.K','Zeta','Blaze','Ryo','Ana'].map(function(n,i){return '<div class="row"><span>'+n+'  <small style="color:var(--mu)">#'+(1200+i*137)+'</small></span><span><span class="mini">Espectar</span><span class="mini">Ir até</span><span class="mini">Kick</span><span class="mini dg">Ban</span></span></div>'}).join('');
$('#as').oninput=function(e){var h=+e.target.value;$('#ah').textContent=(h<10?'0':'')+h+':00'};
$$('#v-admin .wx div').forEach(function(w){w.onclick=function(){$$('#v-admin .wx div').forEach(function(x){x.classList.toggle('on',x===w)})}});
$$('.sub2 div').forEach(function(d){d.onclick=function(){$$('.sub2 div').forEach(function(x){x.classList.toggle('on',x===d)});$$('.as').forEach(function(c){c.classList.toggle('on',c.id==='a-'+d.dataset.a)})}});
$('#q').oninput=function(){var t=this.value.toLowerCase();$$('#al .row').forEach(function(r){r.style.display=r.textContent.toLowerCase().indexOf(t)>-1?'':'none'})};
$('#ar').innerHTML=[['Circuito do porto','Em andamento'],['Descida da serra','Aguardando 4/8'],['Anel do aeroporto','Aguardando 1/6']].map(function(r){return '<div class="row"><span>'+r[0]+'  <small style="color:var(--mu)">'+r[1]+'</small></span><span><span class="mini">Espectar</span><span class="mini">Largar</span><span class="mini dg">Encerrar</span></span></div>'}).join('');
$('#lgl').innerHTML=[['18:42','Nitro','Iniciou a corrida Circuito do porto'],['18:37','Ryo','Kick no jogador #1411'],['18:20','Ana','Alterou o clima global para chuva'],['17:58','Nitro','Limpou veículos abandonados'],['17:31','Ana','Ban no jogador #1098']].map(function(l){return '<div class="row"><span><b style="color:var(--ac)">'+l[0]+'</b>  ·  '+l[1]+'  ·  '+l[2]+'</span></div>'}).join('');
var RP={Nitro:['Admin'],Vortex:['Moderador','VIP'],Kaze:['VIP'],'Drift.K':['Piloto'],Zeta:['Piloto'],Blaze:['VIP'],Ryo:['Moderador'],Ana:['Admin']},sp='Vortex';
function rg(){$('#cgl').innerHTML=Object.keys(RP).map(function(n){return '<div class="row'+(n===sp?' on':'')+'" data-n="'+n+'"><span>'+n+'</span><span>'+RP[n].map(function(r){return '<span class="rc'+(r==='Admin'?' a':'')+'">'+r+'</span>'}).join('')+'</span></div>'}).join('');$('#cn').textContent=sp;$$('#cgl .row').forEach(function(r){r.onclick=function(){sp=r.dataset.n;rg()}})}
function cmsg(t,ok){var m=$('#cm');m.textContent=t;m.style.color=ok?'var(--ac)':'var(--mu)'}
function clog(t){$('#lgl').insertAdjacentHTML('afterbegin','<div class="row"><span><b style="color:var(--ac)">agora</b>  ·  Você  ·  '+t+'</span></div>')}
$('#cd').onclick=function(){var r=$('#cr .pill.on').textContent,l=RP[sp];if(l.indexOf(r)>-1){cmsg(sp+' já tem o cargo '+r+'.',0);return}if(r!=='Piloto'&&l.indexOf('Piloto')>-1)l.splice(l.indexOf('Piloto'),1);l.push(r);rg();cmsg('Cargo '+r+' dado a '+sp+'.',1);clog('Deu o cargo '+r+' para '+sp)};
$('#ct').onclick=function(){var r=$('#cr .pill.on').textContent,l=RP[sp],i=l.indexOf(r);if(r==='Piloto'){cmsg('O cargo Piloto é o padrão e não pode ser removido.',0);return}if(i<0){cmsg(sp+' não tem o cargo '+r+'.',0);return}l.splice(i,1);if(!l.length)l.push('Piloto');rg();cmsg('Cargo '+r+' removido de '+sp+'.',1);clog('Removeu o cargo '+r+' de '+sp)};
rg();
var tt;function toast(t){var e=$('#ts');e.textContent=t;e.classList.add('on');clearTimeout(tt);tt=setTimeout(function(){e.classList.remove('on')},2200)}
var KT={ver:'Pistas verificadas',com:'Corridas da comunidade'};
$$('[data-k]').forEach(function(c){c.onclick=function(){var k=c.dataset.k;if(k==='cri'&&!canCreateRaceTracks){toast('Apenas Master ou Dev podem criar pistas.');return}if(KT[k]){$('#cht').textContent=KT[k];$('#chub').style.display='none';$('#clist').style.display='block';requestApexTracks()}else if(k==='cri'){sendParentNui('apex-start-race-creation')}else if(k==='tre'||k==='tem'||k==='ghost'){requestApexTracks();open2(k)}}});
$('#cback').onclick=function(){$('#clist').style.display='none';$('#chub').style.display=''};

var creatorTracks=[];
var creatorTrackFormat='all';
var canCreateRaceTracks=false;
function applyCreatorPermission(canCreate){
  canCreateRaceTracks=canCreate===true;
  var locked=!canCreateRaceTracks,creatorOption=$('#chub [data-k="cri"]'),newTrack=$('#creator-new-track'),editTrack=$('#ded');
  [creatorOption,newTrack,editTrack].forEach(function(el){if(!el)return;el.classList.toggle('permission-locked',locked);el.setAttribute('aria-disabled',String(locked));el.title=locked?'Disponível somente para Master ou Dev':''});
  if(newTrack)newTrack.disabled=locked;
  if(creatorOption){var description=creatorOption.querySelector('p');if(description)description.textContent=locked?'Disponível somente para jogadores com permissão de criação.':'Desenhe um circuito e coloque sua ideia à prova.'}
  $$('#creator-track-grid .creator-track-card').forEach(function(card){card.disabled=locked;card.classList.toggle('permission-locked',locked);card.setAttribute('aria-disabled',String(locked));card.title=locked?'Disponível somente para Master ou Dev':''});
  resetKeyboardFocus();
}
window.addEventListener('message',function(event){var data=event.data||{};if(data.type==='apex-track-creator-permission')applyCreatorPermission(data.canCreate===true)});
applyCreatorPermission(false);
function creatorTrackRows(tracks){
  creatorTracks=(Array.isArray(tracks)?tracks:[]).map(function(t){return {id:Number(t.id),name:String(t.name||'PISTA SEM NOME'),type:String(t.type||'circuit'),creator:String(t.creator_name||''),laps:Math.max(1,Number(t.laps)||3),cps:Number(t.cps||0)}}).filter(function(t){return t.id>0});
  $('#creator-track-count').textContent=String(creatorTracks.length);
  renderCreatorTrackCards();
}
function renderCreatorTrackCards(){
  var grid=$('#creator-track-grid');
  if(!grid)return;
  var query=($('#creator-track-search').value||'').trim().toLowerCase();
  var visible=creatorTracks.map(function(t,i){return {track:t,index:i}}).filter(function(row){return (creatorTrackFormat==='all'||row.track.type===creatorTrackFormat)&&row.track.name.toLowerCase().includes(query)});
  grid.innerHTML=visible.length?visible.map(function(row){var t=row.track,i=row.index,sprint=t.type==='sprint';return '<button class="creator-track-card '+(sprint?'is-sprint':'is-circuit')+(canCreateRaceTracks?'':' permission-locked')+'" type="button" data-index="'+i+'"'+(canCreateRaceTracks?'':' disabled aria-disabled="true" title="Disponível somente para Master ou Dev"')+'><span class="creator-track-format">'+(sprint?'SPRINT · PONTO A PONTO':'CIRCUITO · POR VOLTAS')+'</span><span class="creator-track-shape" aria-hidden="true">'+(sprint?'➜':'↻')+'</span><strong>'+escapeCreatorText(t.name)+'</strong><small>'+(t.cps)+' CHECKPOINTS'+(sprint?'':' · '+t.laps+' VOLTAS')+'</small><span class="creator-track-edit">EDITAR ↗</span></button>'}).join(''):'<div class="creator-tracks-empty"><b>'+(creatorTracks.length?'NENHUMA PISTA ENCONTRADA':'NENHUMA PISTA CRIADA')+'</b><span>'+(creatorTracks.length?'Tente outro nome ou formato.':'Suas corridas vão aparecer aqui depois de salvar.')+'</span></div>';
  $$('#creator-track-grid .creator-track-card').forEach(function(card){card.onclick=function(){if(!canCreateRaceTracks){toast('Apenas Master ou Dev podem editar pistas.');return}var t=creatorTracks[Number(card.dataset.index)];if(t)sendParentNui('apex-edit-track',{trackId:t.id})}});
  applyCreatorPermission(canCreateRaceTracks);
  resetKeyboardFocus();
}
function escapeCreatorText(value){return String(value).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function openCreatorTracksPage(){go('corridas');$('#chub').style.display='none';$('#clist').style.display='none';$('#clist2').style.display='none';$('#creator-page').style.display='grid';sendParentNui('apex-get-my-tracks');resetKeyboardFocus()}
$('#creator-new-track').onclick=function(){if(!canCreateRaceTracks){toast('Apenas Master ou Dev podem criar pistas.');return}sendParentNui('apex-start-new-track')};
$('#creator-track-search').addEventListener('input',renderCreatorTrackCards);
$$('#creator-track-filters button').forEach(function(button){button.onclick=function(){creatorTrackFormat=button.dataset.format;$$('#creator-track-filters button').forEach(function(b){b.classList.toggle('on',b===button)});renderCreatorTrackCards()}});
$('#creator-back').onclick=function(){ $('#creator-page').style.display='none';$('#chub').style.display='';resetKeyboardFocus() };
window.addEventListener('message',function(event){var d=event.data||{};if(d.type==='apex-open-my-tracks')openCreatorTracksPage();else if(d.type==='apex-my-tracks')creatorTrackRows(d.tracks)});
// TR é alimentado com as pistas reais do apexracing (id, nome, tipo, voltas
// padrão, checkpoints, distância, dificuldade). Enquanto os dados não
// chegam, a lista mostra o estado de carregamento.
var TR=[],TRloading=true,TRavailable=true,ts=0,tfl='Todas',fv={},TRrecords={};
function requestApexTracks(){sendParentNui('apex-get-race-tracks')}
function apexTrackToRow(t){var laps=t.type==='circuit'?Math.max(1,Number(t.laps)||3):1;var diff=Math.max(1,Math.min(5,Math.round((t.checkpoints||0)/3)||1));return[t.name,t.type==='sprint'?'Sprint':'Circuito',laps,t.checkpoints||0,Number(t.distance||0),diff,t.id]}
window.addEventListener('message',function(event){
  var d=event.data;
  if(!d||d.type!=='apex-race-tracks')return;
  TRloading=d.loading===true;
  TRavailable=d.available!==false;
  TR=(d.tracks||[]).map(apexTrackToRow);
  if($('#clist').style.display!=='none')trender();
  if($('#clist2').style.display!=='none')trender2();
});
window.addEventListener('message',function(event){
  var d=event.data;
  if(!d||d.type!=='apex-track-records')return;
  TRrecords[d.trackId]=d.records||{};
  var cur=TR[ts];
  if(cur&&cur[6]===d.trackId)tdet();
});
requestApexTracks();
function prng(a){return function(){a|=0;a=a+0x6D2B79F5|0;var t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
function tp(seed,w,h){var r=prng(seed*977+13),n=8,p=[],i;for(i=0;i<n;i++){var a=i/n*6.2832,rd=.5+.5*r();p.push([w/2+Math.cos(a)*rd*w*.42,h/2+Math.sin(a)*rd*h*.42])}var d='M'+p[0][0].toFixed(1)+' '+p[0][1].toFixed(1);for(i=0;i<n;i++){var p0=p[(i+n-1)%n],p1=p[i],p2=p[(i+1)%n],p3=p[(i+2)%n];d+='C'+(p1[0]+(p2[0]-p0[0])/6).toFixed(1)+' '+(p1[1]+(p2[1]-p0[1])/6).toFixed(1)+' '+(p2[0]-(p3[0]-p1[0])/6).toFixed(1)+' '+(p2[1]-(p3[1]-p1[1])/6).toFixed(1)+' '+p2[0].toFixed(1)+' '+p2[1].toFixed(1)}return d+'Z'}
function dots(n){var h='';for(var i=0;i<5;i++)h+='<i'+(i<n?' class="f"':'')+'></i>';return h}
// Recordes reais vem do apexracing (tabela apex_records). Enquanto nao
// chegam, mostramos "Carregando..." em vez de um tempo inventado.
function requestTrackRecords(id){if(id==null||TRrecords[id])return;sendParentNui('apex-get-track-records',{trackId:id})}
function tdet(){var t=TR[ts];if(!t){$('#dn').textContent=TRloading?'CARREGANDO...':(TRavailable?'NENHUMA PISTA':'APEXRACING OFFLINE');$('#dc').textContent='';$('#d1').textContent='--';$('#d2').textContent='--';$('#d3').textContent='--';$('#d4').innerHTML='';$('#d5').textContent='--';$('#d6').textContent='--';return}$('#dn').textContent=t[0].toUpperCase();$('#dc').textContent='por Equipe Apex';$('#dp').setAttribute('d',tp(ts+1,300,170));$('#d1').textContent=t[2];$('#d2').textContent=t[3];$('#d3').textContent=String(t[4]).replace('.',',')+' km';$('#d4').innerHTML=dots(t[5]);var rec=TRrecords[t[6]];if(!rec){$('#d5').textContent='--';$('#d6').textContent='Carregando…';requestTrackRecords(t[6])}else if(rec.bestTime){$('#d5').textContent=rec.bestTime;$('#d6').textContent=(rec.global&&rec.global[0]&&rec.global[0].player_name)||'--'}else{$('#d5').textContent='--';$('#d6').textContent='Sem recorde ainda'}var format=$('#detailFormat');if(format){format.textContent=t[1]==='Sprint'?'SPRINT / PONTO A PONTO':'CIRCUITO / VOLTAS';$('#td').classList.toggle('is-sprint',t[1]==='Sprint');$('#td').classList.toggle('is-circuit',t[1]!=='Sprint')}$('#dfv').classList.toggle('on',!!fv[ts])}
function trender(an){var scroll=$('#tg').scrollLeft,q=$('#tq').value.toLowerCase(),vis=[];TR.forEach(function(t,i){if((tfl==='Todas'||(tfl==='Favoritas'&&fv[i])||(tfl!=='Favoritas'&&tfl!=='Todas'&&t[1]===tfl))&&t[0].toLowerCase().indexOf(q)>-1)vis.push(i)});if(vis.indexOf(ts)<0&&vis.length)ts=vis[0];$('#tg').innerHTML=vis.map(function(i,k){var t=TR[i],sprint=t[1]==='Sprint';return '<div class="tc track-card '+(sprint?'is-sprint':'is-circuit')+(i===ts?' on':'')+(an?' tin':'')+'" data-i="'+i+'"'+(an?' style="animation-delay:'+(k*45)+'ms"':'')+'><div class="track-card-top"><span class="track-format-mark" aria-hidden="true">'+(sprint?'➜':'↻')+'</span><span class="track-format-label">'+(sprint?'SPRINT · PONTO A PONTO':'CIRCUITO · POR VOLTAS')+'</span><button class="track-fav'+(fv[i]?' on':'')+'" type="button" title="Favoritar pista" aria-label="Favoritar pista">'+(fv[i]?'★':'☆')+'</button><span class="vb" title="Pista verificada pela equipe"><svg class="i"><use href="#ck"/></svg></span></div><svg class="tsv" viewBox="0 0 200 140"><path d="'+tp(i+1,200,140)+'"/></svg><h4>'+t[0]+'</h4><div class="track-card-foot"><span>'+t[2]+(t[2]>1?' VOLTAS':' VOLTA')+' <i>·</i> '+t[3]+' CP</span><b>'+String(t[4]).replace('.',',')+' KM</b></div></div>'}).join('')||'<p style="color:var(--mu)">'+(TRloading?'Carregando pistas…':(TRavailable?'Nenhuma pista encontrada.':'apexracing não está iniciado.'))+'</p>';$('#tg').scrollLeft=scroll;$$('#tg .tc').forEach(function(c){c.onclick=function(e){if(e.target.closest('.track-fav'))return;ts=+c.dataset.i;trender()}});$$('#tg .track-fav').forEach(function(b){b.onclick=function(e){e.stopPropagation();var i=+b.closest('.tc').dataset.i;fv[i]=!fv[i];trender()}});tdet()}
$('#tq').oninput=function(){ $('#tg').scrollLeft=0;trender() };var FL=['Todas','Circuito','Sprint','Favoritas'],fb=0;$$('#tf .pill').forEach(function(p){p.addEventListener('click',function(){var n=p.textContent;if(n===tfl||fb)return;$$('#tf .pill').forEach(function(x){x.classList.toggle('on',x===p)});var g=$('#tg');g.scrollLeft=0;g.style.setProperty('--dx',(FL.indexOf(n)>FL.indexOf(tfl)?3:-3)+'em');tfl=n;fb=1;g.classList.add('out');setTimeout(function(){trender(1);g.scrollLeft=0;g.classList.remove('out');setTimeout(function(){fb=0},350)},220)})});
$('#dfv').onclick=function(){fv[ts]=!fv[ts];trender()};
$('#drc').onclick=function(){var t=TR[ts];if(!t)return;var rec=TRrecords[t[6]];if(!rec){toast('Carregando recordes de '+t[0]+'…');requestTrackRecords(t[6]);return}if(!rec.bestTime){toast('Ainda não há recordes em '+t[0]+'.');return}var top=(rec.global||[]).slice(0,3).map(function(r,i){return (i+1)+'º '+r.player_name+' — '+r.time_formatted}).join('  ·  ');toast('Recordes de '+t[0]+': '+top)};
$$('#td .bt2')[0].onclick=function(){if(TR[ts])toast('Mapa de '+TR[ts][0]+' em breve.')};
$('#ded').onclick=function(){if(!canCreateRaceTracks){toast('Apenas Master ou Dev podem editar pistas.');return}var t=TR[ts];if(!t)return;sendParentNui('apex-edit-track',{trackId:t[6]})};
trender();
var ts2=0,tfl2='Todas',md='tre',fb2=0;
function open2(k){md=k;$('#t2').textContent=k==='tre'?'Treino':(k==='ghost'?'Desafio contra o recorde':'Tomada de tempo');$('#abg').textContent=k==='tre'?'Iniciar treino':(k==='ghost'?'Desafiar recorde':'Iniciar tomada de tempo');$('#chub').style.display='none';$('#clist2').style.display='block';trender2(1)}
function ab2(){var t=TR[ts2];if(!t){$('#abn').textContent=TRloading?'Carregando...':'Nenhuma pista disponível';$('#abd').textContent='';$('#abt').textContent='';return}$('#abp').setAttribute('d',tp(ts2+1,300,170));$('#abn').textContent=t[0];$('#abd').textContent='por Equipe Apex';$('#abType').textContent=t[1];$('#abLaps').textContent=md==='tre'?'∞':t[2];$('#abCP').textContent=t[3];$('#abDistance').textContent=String(t[4]).replace('.',',')+' km';var n=$('#abt');n.textContent=md==='tre'?'Tempo não é salvo':'Seu tempo será salvo';n.className='nt'+(md==='tre'?'':' s')}
function trender2(an){var scroll=$('#tg2').scrollLeft,q=$('#tq2').value.toLowerCase(),vis=[];TR.forEach(function(t,i){if((tfl2==='Todas'||(tfl2==='Favoritas'&&fv[i])||(tfl2!=='Favoritas'&&tfl2!=='Todas'&&t[1]===tfl2))&&t[0].toLowerCase().indexOf(q)>-1)vis.push(i)});if(vis.indexOf(ts2)<0&&vis.length)ts2=vis[0];$('#tg2').innerHTML=vis.map(function(i,k){var t=TR[i],sprint=t[1]==='Sprint';return '<div class="tc track-card '+(sprint?'is-sprint':'is-circuit')+(i===ts2?' on':'')+(an?' tin':'')+'" data-i="'+i+'"'+(an?' style="animation-delay:'+(k*45)+'ms"':'')+'><div class="track-card-top"><span class="track-format-mark" aria-hidden="true">'+(sprint?'➜':'↻')+'</span><span class="track-format-label">'+(sprint?'SPRINT · PONTO A PONTO':'CIRCUITO · POR VOLTAS')+'</span><button class="track-fav'+(fv[i]?' on':'')+'" type="button" title="Favoritar pista" aria-label="Favoritar pista">'+(fv[i]?'★':'☆')+'</button></div><svg class="tsv" viewBox="0 0 200 140"><path d="'+tp(i+1,200,140)+'"/></svg><h4>'+t[0]+'</h4><div class="track-card-foot"><span>'+(md==='tre'?'VOLTA LIVRE':t[2]+(t[2]>1?' VOLTAS':' VOLTA'))+' <i>·</i> '+t[3]+' CP</span><b>'+String(t[4]).replace('.',',')+' KM</b></div></div>'}).join('')||'<p style="color:var(--mu)">'+(TRloading?'Carregando pistas…':(TRavailable?'Nenhuma pista encontrada.':'apexracing não está iniciado.'))+'</p>';$('#tg2').scrollLeft=scroll;$$('#tg2 .tc').forEach(function(c){c.onclick=function(e){if(e.target.closest('.track-fav'))return;ts2=+c.dataset.i;trender2()}});$$('#tg2 .track-fav').forEach(function(b){b.onclick=function(e){e.stopPropagation();var i=+b.closest('.tc').dataset.i;fv[i]=!fv[i];trender2()}});ab2()}
$('#tq2').oninput=function(){$('#tg2').scrollLeft=0;trender2()};
$$('#tf2 .pill').forEach(function(p){p.addEventListener('click',function(){var n=p.textContent;if(n===tfl2||fb2)return;$$('#tf2 .pill').forEach(function(x){x.classList.toggle('on',x===p)});var g=$('#tg2');g.scrollLeft=0;g.style.setProperty('--dx',(FL.indexOf(n)>FL.indexOf(tfl2)?3:-3)+'em');tfl2=n;fb2=1;g.classList.add('out');setTimeout(function(){trender2(1);g.scrollLeft=0;g.classList.remove('out');setTimeout(function(){fb2=0},350)},220)})});
$('#cback2').onclick=function(){$('#clist2').style.display='none';$('#chub').style.display=''};
$('#abm').onclick=function(){if(TR[ts2])toast('Mapa de '+TR[ts2][0]+' em breve.')};
$('#abg').onclick=function(){var t=TR[ts2];if(!t)return;sendParentNui(md==='tre'?'apex-start-race-practice':'apex-start-race-timetrial',{trackId:t[6],laps:t[2]})};
var T=[['Novato','#9aa0b5',0],['Piloto','#5ee0a0',300],['Veloz','#ffb454',1500],['Elite','#5bb8ff',2500],['Campeão','#ff6b6b',3600],['Grão-mestre','#b07cff',5000],['Lenda','#ffd86b',7000]],DV=['I','II','III'],CT=1,CD=1,MP=900;
var PL=[['Nitro',5,1,312,61.2,5480],['Vortex',5,0,287,58.4,5120],['Kaze',4,2,241,52.9,4210],['Drift.K',4,1,198,49.5,3890],['Zeta',4,0,265,47.2,3720],['Blaze',3,2,174,44.8,3310],['Ryo',3,1,221,41.3,2980],['Ana',3,0,156,45.1,2740],['Lira',2,2,203,38.6,2120],['Bruno',2,1,167,36.2,1890],['Tati',2,0,142,34.8,1710],['Max',1,2,120,31.5,1450]],sk='Pontos',rb=0,RF=['Pontos','Vitórias','Corridas'];
function bdg(t,x,z){var c=T[t][1];return '<svg style="width:'+z+'em;height:'+(z*1.1)+'em;flex:none" viewBox="0 0 40 44"><polygon points="20,2 38,12 38,32 20,42 2,32 2,12" fill="#12141e"/><polygon points="20,2 38,12 38,32 20,42 2,32 2,12" fill="'+c+'33" stroke="'+c+'" stroke-width="2.5"/><text x="20" y="27" text-anchor="middle" font-family="Orbitron,sans-serif" font-size="13" font-weight="800" fill="'+c+'">'+x+'</text></svg>'}
function lbl(p){return T[p[1]][0]+(p[1]===6?'':' '+DV[p[2]])}
function bx(p){return p[1]===6?'L':DV[p[2]]}
function av(n){var h=0;for(var i=0;i<n.length;i++)h+=n.charCodeAt(i)*7;return '<span class="av2" style="background:hsl('+(h%360)+',50%,38%)">'+n.charAt(0)+'</span>'}
function fp(n){return n.toLocaleString('pt-BR')}function fw(n){return String(n).replace('.',',')}
function srt(){var i=sk==='Pontos'?5:sk==='Vitórias'?4:3;return PL.slice().sort(function(a,b){return b[i]-a[i]})}
function rrender(an){var c=an?' tin':'';$('#rl2').innerHTML=srt().map(function(p,k){return '<div class="lb'+(k<3?' t'+(k+1):'')+c+'"'+(an?' style="animation-delay:'+(k*35)+'ms"':'')+'><span class="ps">'+(k+1)+'</span>'+av(p[0])+'<span class="nm">'+p[0]+'</span><span class="rk2">'+bdg(p[1],bx(p),1.3)+'<span style="color:'+T[p[1]][1]+'">'+lbl(p)+'</span></span><span class="wb'+(sk==='Vitórias'?' hl':'')+'"><i style="width:'+p[4]+'%"></i><em>'+fw(p[4])+'%</em></span><span class="'+(sk==='Corridas'?'hl':'')+'">'+p[3]+'</span><span class="'+(sk==='Pontos'?'hl':'')+'">'+fp(p[5])+'</span></div>'}).join('')}
$$('#rf .pill').forEach(function(p){p.addEventListener('click',function(){var n=p.textContent;if(n===sk||rb)return;var g=$('#rlw');g.style.setProperty('--dx',(RF.indexOf(n)>RF.indexOf(sk)?3:-3)+'em');sk=n;rb=1;g.classList.add('out');setTimeout(function(){rrender(1);g.classList.remove('out');setTimeout(function(){rb=0},350)},220)})});
function jrn(){var fr=(MP-T[CT][2])/(T[CT+1][2]-T[CT][2]),xm=(CT+.5+fr)/7,h='<div class="jl"></div><div class="jf" style="width:'+((xm-1/14)*100)+'%"></div><div class="jm" style="left:'+(xm*100)+'%">Você  ·  '+fp(MP)+' pts<i></i></div>';for(var t=0;t<7;t++){h+='<div class="jn'+(t===CT?' cur':(t>CT?' up':''))+'" style="--c:'+T[t][1]+'">'+bdg(t,t===CT?DV[CD]:T[t][0].charAt(0),3.4)+'<b>'+T[t][0]+'</b><small>'+fp(T[t][2])+' pts</small></div>'}$('#jt').innerHTML=h}
var NB=[[15,'Duda',1010],[16,'Leo',985],[17,'Isa',940],[18,'Você',900],[19,'Caio',870],[20,'Nina',830],[21,'Otto',790]];
$('#nb').innerHTML=NB.map(function(n){var me=n[1]==='Você',d=n[2]-MP;return '<div class="nr'+(me?' me3':'')+'"><span>'+n[0]+'º</span><span class="nm">'+n[1]+'</span><span>'+fp(n[2])+'</span><span class="d">'+(me?'':(d>0?'+'+d:d))+'</span></div>'}).join('');
$('#tgt').innerHTML='Faltam <b>40 pts</b> para passar Isa e chegar ao 17º';
jrn();rrender();
function mm(s){s=Math.max(0,s|0);return ('0'+Math.floor(s/60)).slice(-2)+':'+('0'+s%60).slice(-2)}
function osw(k){['ohub','omm','ohi'].forEach(function(i){$('#'+i).style.display=i===k?(i==='ohub'?'':'block'):'none'});if(k==='omm')requestAutoHostState()}
$$('[data-o]').forEach(function(c){c.onclick=function(){osw(c.dataset.o==='mm'?'omm':'ohi')}});
$$('#omm [data-b],#ohi [data-b]').forEach(function(b){b.onclick=function(){osw('ohub')}});

// ---- Online real: sala automatica (auto-hoster) do apexracing ----
var autoHostState=null, apexLobbyRoom=null, inQueue=false, autoHostTick=null, multiplayerPickerReturn=false;

function requestAutoHostState(){ sendParentNui('apex-get-autohost-state') }

function phaseLabel(st){
  if(st&&st.phase==='intermission') return 'Intervalo entre corridas';
  if(st&&st.phase==='starting') return 'Preparando a largada';
  if(st&&st.phase==='racing') return 'Corrida iniciada';
  if(!st||!st.lobbyId) return 'Aguardando o servidor abrir uma sala…';
  if(st.phase==='voting') return 'Vote na pista para a corrida começar';
  return 'Preparando a próxima sala…';
}

function renderAutoHostVote(){
  var st=autoHostState, cands=(st&&st.candidates)||[], tally=(st&&st.tally)||[];
  var tot=tally.reduce(function(a,b){return a+(b||0)},0);
  var totalVotes=$('#mp-total-votes');if(totalVotes)totalVotes.textContent=String(tot);
  $('#vt3').innerHTML = cands.length ? cands.map(function(c,i){
    var v=tally[i]||0;
    return '<div class="vc" data-i="'+i+'"><h4>'+c.name+'</h4><div class="mt2">'+(c.type==='circuit'?'Circuito':'Sprint')+'</div><div class="vb2"><i style="width:'+(tot?v/tot*100:0)+'%"></i></div><div class="vn"><b>'+v+'</b> votos</div></div>';
  }).join('') : '<p style="color:var(--mu)">Aguardando a votacao abrir…</p>';
  $$('#vt3 .vc').forEach(function(e){e.onclick=function(){sendParentNui('apex-autohost-vote',{choice:(+e.dataset.i)+1})}});
}

function renderAutoHostStatus(){
  var st=autoHostState;
  $('#mst').textContent=phaseLabel(st);
  var secs=(st&&st.secondsLeft)||0;
  var voting=!!(st&&st.phase==='voting');
  var timerText=voting?mm(secs):st&&st.phase==='intermission'?'INTERVALO':st&&st.phase==='starting'?'PREPARANDO LARGADA':st&&st.phase==='racing'?'CORRIDA INICIADA':'AGUARDANDO';
  $('#mv').textContent=timerText;
  var statusTimer=$('#mv2');if(statusTimer)statusTimer.textContent=timerText;
  var clockLabel=$('#mp-clock-label');if(clockLabel)clockLabel.textContent=voting?'VOTAÇÃO ENCERRA EM':st&&st.phase==='intermission'?'PRÓXIMA CORRIDA':'STATUS';
  var clock=$('.mp-status-clock');if(clock)clock.classList.toggle('is-status',!voting);
  var countdown=$('#mp-countdown');if(countdown)countdown.classList.toggle('is-status',!voting);
  $('#hmq').textContent=st?st.players:0;
  $('#mpc').textContent=st?st.players:0;
  var phase=$('#mp-phase-label');
  if(phase)phase.textContent=st&&st.phase==='intermission'?'INTERVALO':st&&st.phase==='starting'?'PREPARANDO LARGADA':st&&st.phase==='racing'?'CORRIDA INICIADA':!st||!st.lobbyId?'AGUARDANDO SALA':st.phase==='voting'?'VOTAÇÃO ABERTA':'PRÓXIMA SALA';
  var phaseActive=!!(st&&(st.phase==='starting'||st.phase==='racing'||st.phase==='intermission'));
  var multiplayerPanel=$('#omm');if(multiplayerPanel)multiplayerPanel.classList.toggle('is-phase-view',phaseActive);
  var phaseTitle=$('#mp-phase-title'),phaseCopy=$('#mp-phase-copy'),phaseKicker=$('#mp-phase-kicker');
  if(phaseTitle)phaseTitle.textContent=st&&st.phase==='intermission'?'INTERVALO':st&&st.phase==='starting'?'LARGADA EM INSTANTES':'CORRIDA INICIADA';
  if(phaseCopy)phaseCopy.textContent=st&&st.phase==='intermission'?'A próxima disputa está sendo preparada. A votação e a entrada na fila voltam quando uma nova sala abrir.':st&&st.phase==='starting'?'A votação foi encerrada. A corrida começará em instantes.':'A corrida está em andamento. Aguarde o próximo intervalo para entrar na disputa.';
  if(phaseKicker)phaseKicker.textContent=st&&st.phase==='intermission'?'PRÓXIMA DISPUTA':st&&st.phase==='starting'?'PREPARAÇÃO DA LARGADA':'DISPUTA EM ANDAMENTO';
  var btn=$('#qbtn');
  btn.textContent=inQueue?'Sair da fila':'Entrar na fila';
  btn.onclick=inQueue?function(){sendParentNui('apex-leave-autohost')}:function(){if(st&&st.lobbyId)sendParentNui('apex-join-autohost',{lobbyId:st.lobbyId})};
  var changeVehicle=$('#mp-change-vehicle');
  if(changeVehicle){var vehicleLocked=inQueue||!!(st&&(st.phase==='starting'||st.phase==='racing'));changeVehicle.disabled=vehicleLocked;changeVehicle.textContent=vehicleLocked?'TROCA INDISPONÍVEL':'TROCAR VEÍCULO';changeVehicle.title=vehicleLocked?'Saia da fila antes de trocar de veículo':'Escolher outro veículo para a disputa'}
}

var multiplayerVehicleRender=0;
function renderMultiplayerVehicle(vehicle){
  var image=$('#mp-player-vehicle-image'),name=$('#mp-vehicle-name'),brand=$('#mp-vehicle-brand'),modelLine=$('#mp-vehicle-model'),status=$('#mp-vehicle-status'),stage=$('#mp-vehicle-stage');
  if(!image||!stage)return;
  var data=vehicle&&vehicle.available===true?vehicle:null;
  var model=String(data&&data.model||'').trim().toLowerCase();
  var renderId=++multiplayerVehicleRender;
  stage.classList.toggle('has-vehicle',!!data);
  name.textContent=data?String(data.displayName||model||'SEU VEÍCULO').toUpperCase():'ENTRE EM UM VEÍCULO';
  brand.textContent=data?String(data.brand||'SEU VEÍCULO').toUpperCase():'SEU VEÍCULO';
  modelLine.textContent=data?(model.toUpperCase()+' · PRONTO PARA A DISPUTA'):'Entre no seu carro para ver a prévia nesta tela.';
  status.textContent=data?'VEÍCULO ATUAL · '+model.toUpperCase():'NENHUM VEÍCULO DETECTADO';
  image.alt=data?'Prévia do '+String(data.displayName||model):'Nenhum veículo atual detectado';
  image.classList.remove('is-loaded');
  if(!data){image.src='garage-images/vehicle-placeholder.svg';return;}
  var preferred=String(data.image||'').trim();
  resolveMultiplayerVehicleImage(model,preferred).then(function(source){
    if(renderId!==multiplayerVehicleRender||!image.isConnected)return;
    image.onload=function(){image.classList.add('is-loaded')};
    image.onerror=function(){image.classList.remove('is-loaded')};
    image.src=source;
    if(image.complete&&image.naturalWidth>0)image.classList.add('is-loaded');
  });
}

$('#mp-change-vehicle').onclick=function(){if(this.disabled)return;multiplayerPickerReturn=true;sendParentNui('apex-open-multiplayer-vehicle-picker')};
window.addEventListener('message',function(event){
  var data=event.data||{};
  if(data.type==='apex-multiplayer-picker-return'){
    multiplayerPickerReturn=false;
    go('online',true);osw('omm');
    return;
  }
});

function renderQueueList(){
  var players=(apexLobbyRoom&&apexLobbyRoom.players)||[];
  $('#qp').innerHTML = players.length ? players.map(function(p){return '<div class="qr">'+av(p.name||'?')+'<b>'+(p.isSelf?'Você':(p.name||'?'))+'</b></div>'}).join('') : '<p style="color:var(--mu)">Ninguém entrou ainda.</p>';
}

function renderLobbyChat(){
  var hist=(apexLobbyRoom&&apexLobbyRoom.chatHistory)||[];
  var c=$('#mchat');
  c.innerHTML = hist.length ? hist.map(function(m){return '<span><b>'+(m.isSystem?'Sistema':(m.author||'?'))+':</b> '+String(m.message||'').replace(/</g,'&lt;')+'</span>'}).join('') : '<span>Sem mensagens ainda.</span>';
  c.scrollTop=c.scrollHeight;
}

function sendMsg(){var v=$('#mci').value.trim();if(!v)return;sendParentNui('apex-send-lobby-chat',{message:v});$('#mci').value=''}
$('#mcb').onclick=sendMsg;$('#mci').onkeydown=function(e){if(e.key==='Enter')sendMsg()};

renderAutoHostStatus();renderQueueList();renderLobbyChat();renderAutoHostVote();

window.addEventListener('message', function(event) {
  var d=event.data;
  if(!d) return;
  if(d.type==='apex-focus-esc'){ window.focus(); return }
  if(d.type==='apex-multiplayer-vehicle'){ renderMultiplayerVehicle(d.vehicle); return }
  if(d.type==='apex-autohost-state'){ autoHostState=d.state||null; renderAutoHostVote(); renderAutoHostStatus(); return }
  if(d.type==='apex-lobby-room'){ apexLobbyRoom=d.room||null; inQueue=true; renderQueueList(); renderLobbyChat(); renderAutoHostStatus(); return }
  if(d.type==='apex-lobby-room-closed'){ apexLobbyRoom=null; inQueue=false; renderQueueList(); renderLobbyChat(); renderAutoHostStatus(); return }
});
