// BeamNG Weather: Rain Overhaul UI app
// - A small control panel (rain on/off, intensity, wipers, feature toggles)
// - A full-screen canvas behind the other apps that draws raindrops on the
//   windshield in the driver camera. Drops run down the glass, are pushed up
//   by the wind at speed, and are cleared by the wipers.
angular.module('beamng.apps')
.directive('beamngWeatherRain', [function () {
  return {
    template:
      '<div class="bngw-panel">' +
        '<div class="bngw-title"><span>Rain Overhaul</span>' +
          '<button class="bngw-btn" ng-class="{off: !d.rainOn}" ng-click="toggleRain()">{{ d.rainOn ? "Raining" : "Dry" }}</button></div>' +
        '<div class="bngw-row"><span>Intensity</span>' +
          '<input type="range" min="0.05" max="1" step="0.05" ng-model="ui.target" ng-change="setIntensity()">' +
          '<span>{{ (ui.target * 100) | number:0 }}%</span></div>' +
        '<div class="bngw-row"><span>Rain now</span><div class="bngw-bar"><div ng-style="{width: (d.intensity*100)+\'%\'}"></div></div></div>' +
        '<div class="bngw-row"><span>Road wetness</span><div class="bngw-bar"><div ng-style="{width: (d.wetness*100)+\'%\'}"></div></div></div>' +
        '<div class="bngw-row"><span>Wipers</span>' +
          '<button class="bngw-btn" ng-class="{off: d.wipers == 0}" ng-click="cycleWipers()">{{ wiperNames[d.wipers] }}</button></div>' +
        '<div class="bngw-checks">' +
          '<label ng-repeat="f in featureList"><input type="checkbox" ng-model="d.features[f.key]" ng-change="setFeature(f.key)"> {{ f.label }}</label>' +
        '</div>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    link: function (scope, element) {
      var lua = function (cmd) { bngApi.engineLua(cmd); };

      scope.d = { rainOn: false, target: 0.6, intensity: 0, wetness: 0, wipers: 0, speed: 0, camera: '', inCar: false,
                  features: { particles: true, sky: true, roads: true, body: true, grip: true, windshield: true, allCameras: false } };
      scope.ui = { target: 0.6 };
      scope.wiperNames = ['Off', 'Intermittent', 'Slow', 'Fast'];
      scope.featureList = [
        { key: 'particles', label: 'Rain' }, { key: 'sky', label: 'Storm sky' },
        { key: 'roads', label: 'Wet roads' }, { key: 'body', label: 'Wet paint' },
        { key: 'grip', label: 'Wet grip' }, { key: 'windshield', label: 'Windshield' },
        { key: 'allCameras', label: 'Lens drops' }
      ];
      var dragging = false, dragTimer = null;

      scope.toggleRain = function () { lua('beamngWeather_rain.toggleRain()'); };
      scope.cycleWipers = function () { lua('beamngWeather_rain.cycleWipers()'); };
      scope.setIntensity = function () {
        dragging = true;
        clearTimeout(dragTimer);
        dragTimer = setTimeout(function () { dragging = false; }, 600);
        lua('beamngWeather_rain.setIntensity(' + Number(scope.ui.target).toFixed(2) + ')');
      };
      scope.setFeature = function (key) {
        lua('beamngWeather_rain.setFeature("' + key + '", ' + (scope.d.features[key] ? 'true' : 'false') + ')');
      };

      scope.$on('BeamNGWeatherUpdate', function (event, data) {
        if (!data) return;
        scope.$evalAsync(function () {
          scope.d = data;
          if (!dragging) scope.ui.target = data.target;
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

      // Drop sprite, drawn once: clear water bead with a dark rim and highlight
      var sprite = document.createElement('canvas');
      sprite.width = sprite.height = 64;
      (function () {
        var s = sprite.getContext('2d');
        var g = s.createRadialGradient(28, 26, 2, 32, 32, 30);
        g.addColorStop(0.0, 'rgba(255,255,255,0.55)');
        g.addColorStop(0.25, 'rgba(210,225,240,0.20)');
        g.addColorStop(0.75, 'rgba(150,170,190,0.16)');
        g.addColorStop(0.92, 'rgba(20,30,40,0.40)');
        g.addColorStop(1.0, 'rgba(20,30,40,0.0)');
        s.fillStyle = g;
        s.beginPath(); s.arc(32, 32, 30, 0, Math.PI * 2); s.fill();
        s.fillStyle = 'rgba(255,255,255,0.75)';
        s.beginPath(); s.arc(24, 22, 4, 0, Math.PI * 2); s.fill();
      })();

      var drops = [];
      var MAX_DROPS = 900;
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
        var r = (big ? 3 + Math.random() * 4 : 1 + Math.random() * 2.6) * scale;
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
        for (var i = drops.length - 1; i >= 0; i--) {
          var d = drops[i];
          for (var p = 0; p < ps.length; p++) {
            var dx = d.x - ps[p].x, dy = ps[p].y - d.y;
            var dist = Math.sqrt(dx * dx + dy * dy);
            if (dist < L * 0.12 || dist > L) continue;
            var a = Math.atan2(dy, dx);
            if (a >= a0 && a <= a1) { drops.splice(i, 1); break; }
          }
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

      var last = performance.now();
      var running = true;
      function frame(now) {
        if (!running) return;
        var dt = Math.min(0.1, (now - last) / 1000);
        last = now;
        var d = scope.d, f = d.features || {};
        var show = f.windshield && (d.inCar || f.allCameras);
        ctx.clearRect(0, 0, W, H);

        if (!show) { drops.length = 0; requestAnimationFrame(frame); return; }

        var inCar = d.inCar;
        var speed = d.speed || 0;         // m/s
        var rain = d.intensity || 0;

        // New drops: more when it rains harder and when driving fast
        var rate = rain * 140 * (inCar ? (1 + speed / 18) : 0.35);
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
              p.y -= p.vy * dt;
              p.x += p.vx * dt;
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
