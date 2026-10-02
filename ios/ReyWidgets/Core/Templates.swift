import Foundation

enum Templates {
    static var all: [WidgetDocument] {
        var clock = WidgetDocument()
        clock.name = "Quiet hours"; clock.native.layout = .clock
        clock.native.title = "RIGHT HERE, RIGHT NOW"; clock.native.symbol = "sun.horizon"
        clock.native.accent = "#FBCF9A"; clock.native.background = "#30251E"
        clock.native.footer = "A little room to breathe."

        var weather = WidgetDocument()
        weather.name = "Manila weather"; weather.native.title = "MANILA"
        weather.native.value = "{{/current/temperature_2m}}°"
        weather.native.subtitle = "Feels like {{/current/apparent_temperature}}° · Wind {{/current/wind_speed_10m}} km/h"
        weather.native.footer = "Open-Meteo"; weather.native.symbol = "cloud.sun.fill"
        weather.native.accent = "#9AE3FF"; weather.native.background = "#123045"
        weather.api.url = "https://api.open-meteo.com/v1/forecast?latitude=14.60&longitude=120.98&current=temperature_2m,apparent_temperature,wind_speed_10m&timezone=Asia%2FManila"
        weather.sampleJSON = #"{"current":{"temperature_2m":29,"apparent_temperature":33,"wind_speed_10m":12}}"#

        var focus = WidgetDocument()
        focus.name = "Small wins"; focus.native.layout = .list
        focus.native.title = "TODAY'S INTENTIONS"; focus.native.symbol = "checkmark.circle"
        focus.native.accent = "#D7BEFF"; focus.native.background = "#272136"
        focus.native.footer = "Progress at your own pace."

        var goal = WidgetDocument()
        goal.name = "Savings goal"; goal.native.layout = .progress
        goal.native.title = "ONE STEP CLOSER"; goal.native.value = "₱400,000"
        goal.native.subtitle = "40% of a ₱1,000,000 goal"; goal.native.progress = 0.4
        goal.native.footer = "Example • edit your own amount"; goal.native.symbol = "leaf"

        var html = WidgetDocument()
        html.name = "Made of possibility"; html.mode = .html
        html.html = """
        <main>
          <div class="top"><span class="dot"></span> A LITTLE REMINDER <span class="star">✳</span></div>
          <h1>Make it<br> <em>yours.</em></h1>
          <p data-bind="/message"></p>
          <div class="bottom"><span>REYWIDGETS STUDIO</span><span>↗</span></div>
        </main>
        """
        html.css = """
        body{background:#deebcf;color:#1d3023;font-family:system-ui}
        main{height:100%;padding:20px 24px;display:flex;flex-direction:column;position:relative}
        .top,.bottom{display:flex;align-items:center;gap:7px;font:9px ui-monospace,monospace;letter-spacing:1px}
        .dot{width:6px;height:6px;background:#3a7039;border-radius:100%}.star{margin-left:auto;font-size:26px}
        h1{font-size:38px;line-height:.94;letter-spacing:-1.8px;margin:10px 0 8px;font-weight:650}
        h1 br{display:none}em{font-family:Georgia,serif;font-weight:400}
        p{font-size:11px;margin:0;max-width:220px}.bottom{margin-top:auto;font-size:7px;justify-content:space-between;opacity:.65}
        @media(max-width:220px){main{padding:14px}.top{font-size:7px;letter-spacing:0}.star{font-size:20px}h1{font-size:29px}h1 br{display:block}p{font-size:9px}.bottom{font-size:6px}}
        @media(min-height:250px){h1{font-size:68px;margin:30px 0 20px}h1 br{display:block}p{font-size:16px}.top{font-size:11px}}
        """
        html.javascript = "// Edit freely. No internet access is needed for this design.\n"

        var apiHTML = WidgetDocument()
        apiHTML.name = "API canvas"; apiHTML.mode = .html
        apiHTML.api = weather.api; apiHTML.api.credentialID = UUID().uuidString
        apiHTML.sampleJSON = weather.sampleJSON
        apiHTML.html = """
        <main><header>MANILA / WEATHER</header><div class="reading"><strong id="temp"></strong><span>°C</span></div><footer>FEELS LIKE <b data-bind="/current/apparent_temperature"></b>° · OPEN-METEO</footer></main>
        """
        apiHTML.css = """
        body{font-family:system-ui;background:#191e2b;color:#c6d8f4}
        main{height:100%;padding:20px;display:flex;flex-direction:column;justify-content:space-between}
        header,footer{font:9px ui-monospace,monospace;letter-spacing:1px}
        .reading{display:flex;align-items:baseline;gap:8px;color:#afff8b}strong{font-size:66px;font-weight:500;letter-spacing:-4px}
        footer{font-size:8px;opacity:.7}@media(min-height:250px){strong{font-size:128px}}
        """
        apiHTML.javascript = "document.getElementById('temp').textContent = widget.get('/current/temperature_2m');"
        return [clock, weather, focus, goal, html, apiHTML]
    }
}
