// BeamNG Weather: Rain Overhaul UI app
// - Control panel: weather presets, rain intensity, live rain and road
//   wetness meters, wipers, feature switches and timing settings.
// - A full-screen canvas behind the other apps that draws raindrops on the
//   windshield in the driver camera. Drops run down the glass, are pushed up
//   by the wind at speed, and are cleared by the wipers.
(function () {
  // The stylesheet is built into this file so it loads even when the game
  // does not load app.css on its own.
  var CSS = "/* BeamNG Weather: Rain Overhaul panel */\n.bngw {\n  --bg: rgba(16, 20, 27, 0.88);\n  --card: rgba(255, 255, 255, 0.05);\n  --line: rgba(255, 255, 255, 0.09);\n  --text: #e9eef5;\n  --muted: #8d99a8;\n  --accent: #5fb0ff;\n  --accent-2: #8fd0ff;\n  --warn: #ffb35c;\n  --off: #3a424d;\n  width: 100%; height: 100%; box-sizing: border-box;\n  display: flex; flex-direction: column;\n  background: var(--bg); color: var(--text);\n  font-family: \"Segoe UI\", Roboto, Arial, sans-serif; font-size: 12px;\n  border-radius: 10px; border: 1px solid var(--line);\n  overflow: hidden; user-select: none;\n}\n.bngw * { box-sizing: border-box; }\n/* Reset styles the game UI puts on buttons and inputs */\n.bngw button { font-family: inherit; line-height: 1.2; text-transform: none; letter-spacing: normal;\n  min-width: 0; min-height: 0; margin: 0; box-shadow: none; outline: none; }\n.bngw div, .bngw span { line-height: 1.3; }\n.bngw svg { display: block; }\n\n/* Header */\n.bngw-head {\n  display: flex; align-items: center; gap: 8px; padding: 9px 10px;\n  background: linear-gradient(180deg, rgba(95,176,255,0.14), rgba(95,176,255,0));\n  border-bottom: 1px solid var(--line);\n}\n.bngw-head .ico { width: 22px; height: 22px; color: var(--accent); }\n.bngw-head .title { font-size: 13px; font-weight: 600; flex: 1; letter-spacing: 0.2px; }\n.bngw-pill {\n  padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 600;\n  background: var(--off); color: var(--muted);\n}\n.bngw-pill.on { background: rgba(95,176,255,0.22); color: var(--accent-2); }\n.bngw-pill.storm { background: rgba(255,179,92,0.2); color: var(--warn); }\n.bngw-iconbtn {\n  width: 24px; height: 24px; border: 0; border-radius: 6px; padding: 4px;\n  background: transparent; color: var(--muted); cursor: pointer;\n}\n.bngw-iconbtn:hover { background: var(--card); color: var(--text); }\n\n.bngw-body { padding: 8px 10px 10px; overflow-y: auto; flex: 1; }\n.bngw-section { margin-top: 10px; }\n.bngw-section:first-child { margin-top: 2px; }\n.bngw-label {\n  font-size: 10px; font-weight: 700; letter-spacing: 0.8px; text-transform: uppercase;\n  color: var(--muted); margin-bottom: 6px; display: flex; justify-content: space-between;\n}\n.bngw-label .val { color: var(--text); letter-spacing: 0; text-transform: none; font-size: 11px; }\n\n/* Presets */\n.bngw-presets { display: grid; grid-template-columns: repeat(5, 1fr); gap: 4px; }\n.bngw-preset {\n  display: flex; flex-direction: column; align-items: center; gap: 3px;\n  padding: 6px 2px 5px; border-radius: 7px; border: 1px solid var(--line);\n  background: var(--card); color: var(--muted); cursor: pointer; font-size: 10px;\n  transition: background 0.15s, color 0.15s, border-color 0.15s;\n}\n.bngw-preset svg { width: 22px; height: 22px; }\n.bngw-preset:hover { color: var(--text); background: rgba(255,255,255,0.09); }\n.bngw-preset.active { color: var(--accent-2); border-color: var(--accent); background: rgba(95,176,255,0.16); }\n\n/* Slider */\n.bngw-slider { width: 100%; -webkit-appearance: none; appearance: none; height: 6px; border-radius: 3px; outline: none; cursor: pointer; margin: 4px 0; }\n.bngw-slider::-webkit-slider-thumb {\n  -webkit-appearance: none; width: 16px; height: 16px; border-radius: 50%;\n  background: #fff; border: 3px solid var(--accent); box-shadow: 0 1px 4px rgba(0,0,0,0.5);\n}\n.bngw-scale { display: flex; justify-content: space-between; font-size: 10px; color: var(--muted); }\n\n/* Meters */\n.bngw-meters { display: grid; grid-template-columns: 1fr 1fr; gap: 6px; }\n.bngw-meter { background: var(--card); border: 1px solid var(--line); border-radius: 7px; padding: 6px 8px; }\n.bngw-meter .top { display: flex; justify-content: space-between; align-items: baseline; }\n.bngw-meter .name { color: var(--muted); font-size: 10px; text-transform: uppercase; letter-spacing: 0.6px; font-weight: 700; }\n.bngw-meter .num { font-size: 15px; font-weight: 600; }\n.bngw-meter .state { font-size: 10px; color: var(--accent-2); margin-top: 1px; }\n.bngw-track { height: 5px; border-radius: 3px; background: var(--off); overflow: hidden; margin-top: 5px; }\n.bngw-track > div { height: 100%; border-radius: 3px; background: linear-gradient(90deg, #3d8fe0, var(--accent-2)); transition: width 0.2s linear; }\n\n/* Segmented control */\n.bngw-seg { display: grid; grid-template-columns: repeat(4, 1fr); background: var(--card); border: 1px solid var(--line); border-radius: 7px; padding: 2px; gap: 2px; }\n.bngw-seg button {\n  border: 0; border-radius: 5px; padding: 5px 0; font-size: 11px; cursor: pointer;\n  background: transparent; color: var(--muted);\n}\n.bngw-seg button:hover { color: var(--text); }\n.bngw-seg button.active { background: var(--accent); color: #08121e; font-weight: 600; }\n\n/* Toggles */\n.bngw-toggles { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 10px; }\n.bngw-toggle { display: flex; align-items: center; justify-content: space-between; padding: 4px 0; cursor: pointer; }\n.bngw-toggle span { color: var(--text); }\n.bngw-switch { position: relative; width: 28px; height: 16px; border-radius: 8px; background: var(--off); transition: background 0.15s; flex: none; }\n.bngw-switch::after {\n  content: \"\"; position: absolute; top: 2px; left: 2px; width: 12px; height: 12px; border-radius: 50%;\n  background: #cfd6df; transition: left 0.15s, background 0.15s;\n}\n.bngw-switch.on { background: var(--accent); }\n.bngw-switch.on::after { left: 14px; background: #fff; }\n\n/* Buttons */\n.bngw-btn {\n  border: 1px solid var(--line); border-radius: 6px; padding: 6px 8px; font-size: 11px; cursor: pointer;\n  background: var(--card); color: var(--text);\n}\n.bngw-btn:hover { background: rgba(255,255,255,0.1); }\n.bngw-btn.primary { background: var(--accent); color: #08121e; border-color: var(--accent); font-weight: 600; }\n.bngw-btn.primary.stop { background: var(--off); color: var(--text); border-color: var(--off); }\n.bngw-btns { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 4px; }\n.bngw-main { width: 100%; padding: 8px; font-size: 12px; margin-top: 8px; }\n\n.bngw-adv-toggle { width: 100%; display: flex; justify-content: space-between; align-items: center; background: transparent; border: 0; color: var(--muted); cursor: pointer; padding: 4px 0; font-size: 11px; border-top: 1px solid var(--line); margin-top: 10px; padding-top: 8px; }\n.bngw-adv-toggle:hover { color: var(--text); }\n.bngw-diag { background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.09); border-radius: 7px; padding: 6px 8px; font-size: 11px; }\n.bngw-diag div { display: flex; justify-content: space-between; gap: 8px; padding: 1px 0; }\n.bngw-diag span { color: #8d99a8; white-space: nowrap; }\n.bngw-diag b { font-weight: 600; text-align: right; color: #e9eef5; }\n.bngw-hint { color: var(--muted); font-size: 10px; margin-top: 6px; line-height: 1.4; }\n\n/* Compact mode */\n.bngw.compact { height: auto; }\n.bngw-mini { display: flex; gap: 6px; padding: 8px 10px; align-items: center; }\n.bngw-mini .bngw-track { flex: 1; margin: 0; }\n.bngw-mini .lbl { color: var(--muted); font-size: 10px; width: 34px; }\n\n/* Windshield overlay, behind the other apps */\n.bngw-overlay { position: fixed; left: 0; top: 0; width: 100vw; height: 100vh; pointer-events: none; z-index: 2147483000; }\n";
  function ensureStyle() {
    if (document.getElementById('bngw-style')) return;
    var st = document.createElement('style');
    st.id = 'bngw-style';
    st.textContent = CSS;
    (document.head || document.documentElement).appendChild(st);
  }

  // Small line icons (inherit the text color)
  var I = {
    cloud: '<path d="M7 18h10a4 4 0 0 0 .6-7.95A6 6 0 0 0 6.1 9.2 4.5 4.5 0 0 0 7 18z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    drizzle: '<path d="M7 14h10a3.5 3.5 0 0 0 .5-6.96A5 5 0 0 0 7.8 6.5 4 4 0 0 0 7 14z"/><path d="M9 17v1M13 18v1M17 17v1"/>',
    rain: '<path d="M7 13h10a3.5 3.5 0 0 0 .5-6.96A5 5 0 0 0 7.8 5.5 4 4 0 0 0 7 13z"/><path d="M8 16l-1 3M12 16l-1 3M16 16l-1 3"/>',
    storm: '<path d="M7 12h10a3.5 3.5 0 0 0 .5-6.96A5 5 0 0 0 7.8 4.5 4 4 0 0 0 7 12z"/><path d="M13 13l-3 4h3l-2 4"/><path d="M7 15l-1 3M17 15l-1 3"/>',
    downpour: '<path d="M7 11h10a3.5 3.5 0 0 0 .5-6.96A5 5 0 0 0 7.8 3.5 4 4 0 0 0 7 11z"/><path d="M6 14l-1.5 5M10 14l-1.5 5M14 14l-1.5 5M18 14l-1.5 5"/>',
    minus: '<path d="M6 12h12"/>',
    plus: '<path d="M6 12h12M12 6v12"/>',
    chev: '<path d="M6 9l6 6 6-6"/>'
  };
  function icon(name) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + I[name] + '</svg>';
  }

  var PRESETS = [
    { key: 'clear',    label: 'Clear',    value: 0 },
    { key: 'drizzle',  label: 'Drizzle',  value: 0.2 },
    { key: 'rain',     label: 'Rain',     value: 0.5 },
    { key: 'storm',    label: 'Storm',    value: 0.8 },
    { key: 'downpour', label: 'Downpour', value: 1 }
  ];
  var ICON_OF = { clear: 'sun', drizzle: 'drizzle', rain: 'rain', storm: 'storm', downpour: 'downpour' };

  var presetHtml = PRESETS.map(function (p) {
    return '<button class="bngw-preset" ng-class="{active: activePreset() == \'' + p.key + '\'}" ng-click="preset(' + p.value + ')">' +
      icon(ICON_OF[p.key]) + '<span>' + p.label + '</span></button>';
  }).join('');

  var TEMPLATE = [
    '<div class="bngw" ng-class="{compact: ui.compact}">',
      '<div class="bngw-head">',
        '<div class="ico">', icon('cloud'), '</div>',
        '<div class="title">Rain Overhaul</div>',
        '<div class="bngw-pill" ng-class="{on: d.rainOn, storm: d.rainOn && ui.target >= 0.8}">{{ weatherName() }}</div>',
        '<button class="bngw-iconbtn" ng-click="toggleCompact()" title="Compact view">', '<span ng-if="!ui.compact">', icon('minus'), '</span><span ng-if="ui.compact">', icon('plus'), '</span></button>',
      '</div>',

      // Compact view: just the two meters
      '<div ng-if="ui.compact">',
        '<div class="bngw-mini"><span class="lbl">Rain</span><div class="bngw-track"><div ng-style="{width: pct(d.intensity)}"></div></div></div>',
        '<div class="bngw-mini" style="padding-top:0"><span class="lbl">Road</span><div class="bngw-track"><div ng-style="{width: pct(d.wetness)}"></div></div></div>',
      '</div>',

      '<div class="bngw-body" ng-if="!ui.compact">',
        '<div class="bngw-section">',
          '<div class="bngw-label">Weather</div>',
          '<div class="bngw-presets">', presetHtml, '</div>',
        '</div>',

        '<div class="bngw-section">',
          '<div class="bngw-label">Intensity <span class="val">{{ (ui.target * 100) | number:0 }}%</span></div>',
          '<input class="bngw-slider" type="range" min="0.05" max="1" step="0.01" ng-model="ui.target" ng-change="setIntensity()" ng-style="sliderStyle(ui.target, 0.05, 1)">',
          '<div class="bngw-scale"><span>Drizzle</span><span>Rain</span><span>Downpour</span></div>',
          '<button class="bngw-btn primary bngw-main" ng-class="{stop: d.rainOn}" ng-click="toggleRain()">{{ d.rainOn ? "Stop rain" : "Start rain" }}</button>',
        '</div>',

        '<div class="bngw-section bngw-meters">',
          '<div class="bngw-meter"><div class="top"><span class="name">Rain now</span><span class="num">{{ (d.intensity * 100) | number:0 }}%</span></div>',
            '<div class="bngw-track"><div ng-style="{width: pct(d.intensity)}"></div></div><div class="state">{{ rainState() }}</div></div>',
          '<div class="bngw-meter"><div class="top"><span class="name">Road</span><span class="num">{{ (d.wetness * 100) | number:0 }}%</span></div>',
            '<div class="bngw-track"><div ng-style="{width: pct(d.wetness)}"></div></div><div class="state">{{ roadState() }}</div></div>',
        '</div>',

        '<div class="bngw-section">',
          '<div class="bngw-label">Wipers</div>',
          '<div class="bngw-seg"><button ng-repeat="w in wiperNames track by $index" ng-class="{active: d.wipers == $index}" ng-click="setWipers($index)">{{ w }}</button></div>',
          '<div class="bngw-hint" ng-style="{color: d.inCar ? \'#8fd0ff\' : \'#8d99a8\'}">{{ windshieldStatus() }}</div>',
        '</div>',

        '<div class="bngw-section">',
          '<div class="bngw-label">Effects</div>',
          '<div class="bngw-toggles">',
            '<div class="bngw-toggle" ng-repeat="f in featureList" ng-click="toggleFeature(f.key)" title="{{ f.tip }}"><span>{{ f.label }}</span><div class="bngw-switch" ng-class="{on: d.features[f.key]}"></div></div>',
          '</div>',
        '</div>',

        '<button class="bngw-adv-toggle" ng-click="ui.advanced = !ui.advanced; saveUi()"><span>Advanced</span>',
          '<span ng-style="{transform: ui.advanced ? \'rotate(180deg)\' : \'none\'}" style="width:16px;height:16px;display:inline-block">', icon('chev'), '</span></button>',
        '<div ng-if="ui.advanced">',
          '<div class="bngw-section">',
            '<div class="bngw-label">Rain quality</div>',
            '<div class="bngw-seg"><button ng-repeat="q in qualities" ng-class="{active: d.quality == q.key}" ng-click="setQuality(q.key)">{{ q.label }}</button></div>',
          '</div>',
          '<div class="bngw-section">',
            '<div class="bngw-label">Time to soak <span class="val">{{ ui.wetSeconds }} s</span></div>',
            '<input class="bngw-slider" type="range" min="10" max="180" step="5" ng-model="ui.wetSeconds" ng-change="setRates()" ng-style="sliderStyle(ui.wetSeconds, 10, 180)">',
          '</div>',
          '<div class="bngw-section">',
            '<div class="bngw-label">Time to dry <span class="val">{{ dryLabel() }}</span></div>',
            '<input class="bngw-slider" type="range" min="30" max="900" step="15" ng-model="ui.drySeconds" ng-change="setRates()" ng-style="sliderStyle(ui.drySeconds, 30, 900)">',
          '</div>',
          '<div class="bngw-section bngw-btns">',
            '<button class="bngw-btn" ng-click="setWetness(0)">Dry roads</button>',
            '<button class="bngw-btn" ng-click="setWetness(1)">Soak roads</button>',
            '<button class="bngw-btn" ng-click="resetSettings()">Reset all</button>',
          '</div>',
          '<div class="bngw-section">',
            '<div class="bngw-label">Diagnostics</div>',
            '<div class="bngw-diag">',
              '<div><span>Map loaded</span><b>{{ d.diag.mapLoaded ? "yes" : "no" }}</b></div>',
              '<div><span>Rain</span><b>{{ d.diag.rain || "-" }}</b></div>',
              '<div><span>Splashes</span><b>{{ d.diag.splashes || "-" }}</b></div>',
              '<div><span>Car drops</span><b>{{ d.diag.carDrops || "-" }}</b></div>',
              '<div><span>Wet roads</span><b>{{ d.diag.roads || "-" }}</b></div>',
              '<div><span>Camera</span><b>{{ d.camera }}{{ d.inCar ? " (in car)" : "" }}</b></div>',
              '<div><span>Windshield drops drawn</span><b>{{ overlayCount }}</b></div>',
            '</div>',
          '</div>',
          '<div class="bngw-hint">Windshield drops show in the driver camera. Turn on Lens drops to see them in outside cameras too. Wet grip is experimental and may cause a short pause when it changes.</div>',
        '</div>',
      '</div>',
    '</div>'
  ].join('');

  angular.module('beamng.apps')
  .directive('beamngWeatherRain', [function () {
    return {
      template: TEMPLATE,
      replace: true,
      restrict: 'EA',
      link: function (scope, element) {
        ensureStyle();
        var lua = function (cmd) { bngApi.engineLua(cmd); };

        scope.d = { rainOn: false, target: 0.6, intensity: 0, wetness: 0, wipers: 0, speed: 0, camera: '', inCar: false,
                    wetSeconds: 45, drySeconds: 240,
                    features: { particles: true, sky: true, roads: true, body: true, grip: true, windshield: true, allCameras: false } };

        // Panel view state, remembered between sessions
        var saved = {};
        try { saved = JSON.parse(localStorage.getItem('bngwRainUi') || '{}') || {}; } catch (e) { saved = {}; }
        scope.ui = { target: 0.6, wetSeconds: 45, drySeconds: 240, compact: !!saved.compact, advanced: !!saved.advanced };
        scope.saveUi = function () {
          try { localStorage.setItem('bngwRainUi', JSON.stringify({ compact: scope.ui.compact, advanced: scope.ui.advanced })); } catch (e) {}
        };
        scope.toggleCompact = function () { scope.ui.compact = !scope.ui.compact; scope.saveUi(); };

        scope.wiperNames = ['Off', 'Interval', 'Slow', 'Fast'];
        scope.featureList = [
          { key: 'particles',  label: 'Rain',       tip: 'Falling rain' },
          { key: 'splashes',   label: '3D splashes', tip: 'Droplets and ripples where the rain lands' },
          { key: 'sky',        label: 'Storm sky',  tip: 'Clouds, fog and wind follow the rain' },
          { key: 'roads',      label: 'Wet roads',  tip: 'Glossy, reflective roads' },
          { key: 'body',       label: 'Wet paint',  tip: 'Soaked, glossy car paint' },
          { key: 'droplets',   label: 'Car drops',  tip: 'Water beads on the paint and windows' },
          { key: 'windshield', label: 'Windshield', tip: 'Drops and wipers in the driver camera' },
          { key: 'allCameras', label: 'Lens drops', tip: 'Drops on the camera in outside views' },
          { key: 'grip',       label: 'Wet grip',   tip: 'Less grip on wet roads (experimental)' }
        ];

        scope.qualities = [{ key: 'low', label: 'Low' }, { key: 'medium', label: 'Medium' }, { key: 'high', label: 'High' }, { key: 'ultra', label: 'Ultra' }];
        scope.setQuality = function (q) { scope.d.quality = q; lua('beamngWeather_rain.setQuality("' + q + '")'); };
        scope.windshieldStatus = function () {
          var f = scope.d.features || {};
          var cam = scope.d.camera || 'unknown';
          if (!f.windshield) return 'Windshield drops are off';
          if (scope.d.inCar) return 'Windshield drops on (camera: ' + cam + ')';
          if (f.allCameras) return 'Lens drops on (camera: ' + cam + ')';
          return 'Windshield drops show in the driver camera (now: ' + cam + '). Press C to switch.';
        };
        scope.pct = function (v) { return Math.round((v || 0) * 100) + '%'; };
        scope.sliderStyle = function (v, min, max) {
          var p = ((v - min) / (max - min)) * 100;
          return { background: 'linear-gradient(90deg, #5fb0ff ' + p + '%, #3a424d ' + p + '%)' };
        };
        scope.weatherName = function () {
          if (!scope.d.rainOn) return scope.d.intensity > 0.01 ? 'Clearing' : 'Dry';
          var t = scope.ui.target;
          if (t < 0.3) return 'Drizzle';
          if (t < 0.65) return 'Rain';
          if (t < 0.9) return 'Storm';
          return 'Downpour';
        };
        scope.activePreset = function () {
          if (!scope.d.rainOn) return 'clear';
          var best = null, dist = 1;
          PRESETS.forEach(function (p) {
            if (p.value > 0 && Math.abs(p.value - scope.ui.target) < dist) { dist = Math.abs(p.value - scope.ui.target); best = p.key; }
          });
          return dist <= 0.05 ? best : null;
        };
        scope.rainState = function () {
          var i = scope.d.intensity || 0;
          if (i < 0.01) return 'No rain';
          if (scope.d.rainOn && i < scope.ui.target - 0.02) return 'Building up';
          if (!scope.d.rainOn) return 'Easing off';
          return 'Steady';
        };
        scope.roadState = function () {
          var w = scope.d.wetness || 0;
          if (w < 0.05) return 'Dry';
          if (w < 0.33) return 'Damp';
          if (w < 0.7) return 'Wet';
          return 'Soaked';
        };
        scope.dryLabel = function () {
          var s = scope.ui.drySeconds;
          return s < 60 ? s + ' s' : (Math.floor(s / 60) + ' min' + (s % 60 ? ' ' + (s % 60) + ' s' : ''));
        };

        // Do not let live updates move a slider while it is being dragged
        var holdUntil = 0;
        function hold() { holdUntil = Date.now() + 700; }

        scope.toggleRain = function () { lua('beamngWeather_rain.toggleRain()'); };
        scope.preset = function (v) {
          hold();
          if (v > 0) scope.ui.target = v;
          lua('beamngWeather_rain.setIntensity(' + Number(v).toFixed(2) + ')');
        };
        scope.setIntensity = function () {
          hold();
          lua('beamngWeather_rain.setIntensity(' + Number(scope.ui.target).toFixed(2) + ')');
        };
        scope.setWipers = function (i) { scope.d.wipers = i; lua('beamngWeather_rain.setWipers(' + i + ')'); };
        scope.toggleFeature = function (key) {
          var on = !scope.d.features[key];
          scope.d.features[key] = on;
          lua('beamngWeather_rain.setFeature("' + key + '", ' + (on ? 'true' : 'false') + ')');
        };
        scope.setRates = function () {
          hold();
          lua('beamngWeather_rain.setRates(' + Number(scope.ui.wetSeconds) + ', ' + Number(scope.ui.drySeconds) + ')');
        };
        scope.setWetness = function (v) { lua('beamngWeather_rain.setWetness(' + v + ')'); };
        scope.resetSettings = function () { lua('beamngWeather_rain.resetSettings()'); };

        scope.$on('BeamNGWeatherUpdate', function (event, data) {
          if (!data) return;
          scope.$evalAsync(function () {
            scope.d = data;
            if (Date.now() > holdUntil) {
              scope.ui.target = data.target;
              if (data.wetSeconds) scope.ui.wetSeconds = data.wetSeconds;
              if (data.drySeconds) scope.ui.drySeconds = data.drySeconds;
            }
          });
        });

      // ---------------------------------------------------------------
      // Windshield overlay
      // ---------------------------------------------------------------
      // Only one overlay, even if the app is added twice
      var old = document.getElementById('bngw-windshield');
      if (old && old.parentNode) old.parentNode.removeChild(old);
      var canvas = document.createElement('canvas');
      canvas.id = 'bngw-windshield';
      canvas.className = 'bngw-overlay';
      // Inline styles: the overlay must never take up space in the page
      canvas.style.cssText = 'position:fixed;left:0;top:0;width:100vw;height:100vh;pointer-events:none;z-index:2147483000;display:block;';
      document.body.insertBefore(canvas, document.body.firstChild);
      var ctx = canvas.getContext('2d');
      var W = 0, H = 0, scale = 1;

      function resize() {
        W = canvas.width = window.innerWidth;
        H = canvas.height = window.innerHeight;
        scale = H / 1080;
      }
      resize();
      window.addEventListener('resize', resize);

      // Drop sprite, drawn once. A water bead on glass works like a tiny lens:
      // it shows the bright sky flipped, so it is light at the bottom and
      // dark at the top, with a sharp rim and a small highlight.
      var sprite = document.createElement('canvas');
      sprite.width = sprite.height = 64;
      (function () {
        var s = sprite.getContext('2d');
        var body = s.createLinearGradient(0, 4, 0, 60);
        body.addColorStop(0.0, 'rgba(30,38,48,0.55)');
        body.addColorStop(0.45, 'rgba(120,135,150,0.30)');
        body.addColorStop(1.0, 'rgba(235,242,250,0.60)');
        s.fillStyle = body;
        s.beginPath(); s.arc(32, 32, 28, 0, Math.PI * 2); s.fill();
        var rim = s.createRadialGradient(32, 32, 20, 32, 32, 30);
        rim.addColorStop(0.0, 'rgba(0,0,0,0)');
        rim.addColorStop(0.8, 'rgba(10,16,24,0.35)');
        rim.addColorStop(1.0, 'rgba(10,16,24,0)');
        s.fillStyle = rim;
        s.beginPath(); s.arc(32, 32, 30, 0, Math.PI * 2); s.fill();
        s.fillStyle = 'rgba(255,255,255,0.85)';
        s.beginPath(); s.ellipse(24, 20, 5, 3.5, -0.5, 0, Math.PI * 2); s.fill();
        s.fillStyle = 'rgba(255,255,255,0.35)';
        s.beginPath(); s.ellipse(38, 50, 9, 3, 0, 0, Math.PI * 2); s.fill();
      })();

      var trails = [];           // wet streaks left by running drops
      var MAX_TRAILS = 600;
      var drops = [];
      var MAX_DROPS = 1400;
      var spawnAcc = 0;

      // Wipers: two arms with pivots at the bottom of the screen
      var wiper = { phase: 0, pause: 0, angle: Math.PI, prevAngle: Math.PI };
      var REST = Math.PI, TOP = Math.PI * 0.42;
      var PERIODS = [0, 1.3, 1.3, 0.75];

      function pivots() {
        return [{ x: W * 0.22, y: H * 1.03 }, { x: W * 0.60, y: H * 1.03 }];
      }
      function armLen() { return H * 0.78; }

      function spawnDrop(big) {
        var r = (big ? 4 + Math.random() * 5 : 1.4 + Math.random() * 3) * scale;
        drops.push({ x: Math.random() * W, y: Math.random() * H, r: r, vy: 0, vx: 0,
                     life: 1, stick: Math.random() * 1.5 });
      }

      function updateWipers(dt) {
        wiper.prevAngle = wiper.angle;
        var mode = scope.d.wipers || 0;
        if (mode === 0 && wiper.phase === 0) { wiper.angle = REST; return; }
        if (wiper.pause > 0) { wiper.pause -= dt; wiper.angle = REST; return; }
        var period = PERIODS[mode] || 1.3;
        wiper.phase += dt / period;
        if (wiper.phase >= 1) {
          wiper.phase = 0;
          if (mode === 1) wiper.pause = 4;   // intermittent: wait between wipes
        }
        // Up and back down, eased
        var t = 0.5 - 0.5 * Math.cos(wiper.phase * Math.PI * 2);
        wiper.angle = REST + (TOP - REST) * t;
      }

      // Remove drops in the area swept since the last frame
      function wipe() {
        if (wiper.angle === wiper.prevAngle) return;
        var a0 = Math.min(wiper.angle, wiper.prevAngle) - 0.03;
        var a1 = Math.max(wiper.angle, wiper.prevAngle) + 0.03;
        var L = armLen(), ps = pivots();
        function swept(x, y) {
          for (var p = 0; p < ps.length; p++) {
            var dx = x - ps[p].x, dy = ps[p].y - y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < L * 0.12 || dist > L) continue;
            var a = Math.atan2(dy, dx);
            if (a >= a0 && a <= a1) return true;
          }
          return false;
        }
        for (var i = drops.length - 1; i >= 0; i--) {
          if (swept(drops[i].x, drops[i].y)) drops.splice(i, 1);
        }
        for (var k = trails.length - 1; k >= 0; k--) {
          var tr = trails[k];
          if (swept((tr.x1 + tr.x2) / 2, (tr.y1 + tr.y2) / 2)) trails.splice(k, 1);
        }
      }

      function drawWipers() {
        var L = armLen(), ps = pivots();
        ctx.lineCap = 'round';
        for (var p = 0; p < ps.length; p++) {
          var ex = ps[p].x + Math.cos(wiper.angle) * L, ey = ps[p].y - Math.sin(wiper.angle) * L;
          var sx = ps[p].x + Math.cos(wiper.angle) * L * 0.12, sy = ps[p].y - Math.sin(wiper.angle) * L * 0.12;
          ctx.strokeStyle = 'rgba(10,10,12,0.92)';
          ctx.lineWidth = 9 * scale;
          ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(ex, ey); ctx.stroke();
          ctx.strokeStyle = 'rgba(60,60,66,0.9)';
          ctx.lineWidth = 3 * scale;
          ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(ex, ey); ctx.stroke();
        }
      }

      var countTimer = 0;
      scope.overlayCount = 0;
      var last = performance.now();
      var running = true;
      function frame(now) {
        if (!running) return;
        var dt = Math.min(0.1, (now - last) / 1000);
        last = now;
        var d = scope.d, f = d.features || {};
        var show = f.windshield && (d.inCar || f.allCameras) && !d.paused;
        countTimer += dt;
        if (countTimer > 0.5) { countTimer = 0; var c = drops.length; scope.$evalAsync(function () { scope.overlayCount = c; }); }
        ctx.clearRect(0, 0, W, H);

        if (!show) { drops.length = 0; trails.length = 0; requestAnimationFrame(frame); return; }

        var inCar = d.inCar;
        var speed = d.speed || 0;         // m/s
        var rain = d.intensity || 0;

        // New drops: more when it rains harder and when driving fast
        var rate = rain * 220 * (inCar ? (1 + speed / 18) : 0.35);
        spawnAcc += rate * dt;
        while (spawnAcc >= 1 && drops.length < MAX_DROPS) {
          spawnAcc -= 1;
          spawnDrop(Math.random() < 0.18);
        }
        if (spawnAcc > 5) spawnAcc = 0;

        // Wind on the glass pushes drops up at speed; gravity pulls big ones down
        var air = inCar ? Math.max(0, speed - 12) * 9 * scale : 0;
        var dry = rain <= 0.01 ? 0.12 : 0.0;    // slowly fade when the rain stops

        for (var i = drops.length - 1; i >= 0; i--) {
          var p = drops[i];
          p.life -= dt * (0.02 + dry + (inCar ? 0 : 0.15));
          if (p.life <= 0) { drops.splice(i, 1); continue; }
          if (p.stick > 0) { p.stick -= dt; }
          else {
            var heavy = p.r / scale;
            var grav = heavy > 3 ? (heavy - 3) * 22 * scale : 0;
            var push = heavy > 1.5 ? air * (heavy / 4) : 0;
            p.vy = -grav + push;                 // screen up is negative y
            p.vx = inCar ? (Math.sin(p.y * 0.01 + p.x * 0.003) * 4 * scale) : 0;
            if (p.vy !== 0) {
              var ox = p.x, oy = p.y;
              p.y -= p.vy * dt;
              p.x += p.vx * dt;
              if (trails.length < MAX_TRAILS) trails.push({ x1: ox, y1: oy, x2: p.x, y2: p.y, w: p.r * 0.7, life: 1 });
              // Moving drops leave tiny beads behind
              if (Math.random() < 3 * dt && drops.length < MAX_DROPS) {
                drops.push({ x: p.x, y: p.y + (p.vy > 0 ? p.r : -p.r), r: p.r * 0.35, vy: 0, vx: 0, life: p.life * 0.6, stick: 99 });
              }
            }
          }
          if (p.y < -20 || p.y > H + 20) { drops.splice(i, 1); continue; }
        }

        if (inCar) { updateWipers(dt); wipe(); }

        // Thin water film makes the view a little grey in heavy rain
        if (inCar && rain > 0) {
          ctx.fillStyle = 'rgba(140,150,160,' + (0.05 * rain).toFixed(3) + ')';
          ctx.fillRect(0, 0, W, H);
        }

        // Wet streaks fade over a few seconds
        ctx.lineCap = 'round';
        for (var t = trails.length - 1; t >= 0; t--) {
          var tr = trails[t];
          tr.life -= dt * 0.35;
          if (tr.life <= 0) { trails.splice(t, 1); continue; }
          ctx.strokeStyle = 'rgba(200,214,228,' + (0.16 * tr.life).toFixed(3) + ')';
          ctx.lineWidth = tr.w;
          ctx.beginPath(); ctx.moveTo(tr.x1, tr.y1); ctx.lineTo(tr.x2, tr.y2); ctx.stroke();
        }

        for (var j = 0; j < drops.length; j++) {
          var q = drops[j];
          var stretch = 1 + Math.min(2.5, Math.abs(q.vy) / (60 * scale));
          var w = q.r * 2, h = q.r * 2 * stretch;
          ctx.globalAlpha = Math.min(1, q.life * 1.5);
          ctx.drawImage(sprite, q.x - w / 2, q.y - h / 2, w, h);
        }
        ctx.globalAlpha = 1;

        if (inCar && (d.wipers > 0 || wiper.phase > 0)) drawWipers();
        requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);

      lua('if beamngWeather_rain then beamngWeather_rain.requestUIUpdate() end');

      scope.$on('$destroy', function () {
        running = false;
        window.removeEventListener('resize', resize);
        if (canvas.parentNode) canvas.parentNode.removeChild(canvas);
      });
    }
  };
}]);
})();
