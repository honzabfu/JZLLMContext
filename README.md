# JZLLMContext

Utilita pro macOS menu bar, která zpracovává obsah schránky pomocí jazykových modelů. Zkopíruješ text nebo obrázek, stiskneš globální zkratku a vybraná akce (překlad, přepis, shrnutí, …) pošle obsah do LLM a vrátí výsledek. Každá akce má vlastní systémový prompt, provider, model a parametry.

---

## Obsah

- [Funkce](#funkce)
- [Požadavky](#požadavky)
- [Instalace a sestavení](#instalace-a-sestavení)
- [Uživatelská příručka](#uživatelská-příručka)
  - [Základní použití](#základní-použití)
  - [Menu bar](#menu-bar)
  - [Overlay panel](#overlay-panel)
  - [Nastavení – Obecné](#nastavení--obecné)
  - [Nastavení – Akce](#nastavení--akce)
  - [Nastavení – Providery](#nastavení--providery)
  - [Nastavení – Zkratka](#nastavení--zkratka)
- [Vlastní modely](#vlastní-modely)
- [Vlastní OpenAI-compatible provider](#vlastní-openai-compatible-provider)
- [Technický popis](#technický-popis)
  - [Architektura](#architektura)
  - [Ukládání konfigurace](#ukládání-konfigurace)
  - [Ukládání API klíčů](#ukládání-api-klíčů)
  - [Struktura konfiguračního souboru](#struktura-konfiguračního-souboru)
  - [Providery a jejich limity](#providery-a-jejich-limity)
  - [OCR pipeline](#ocr-pipeline)
  - [Globální zkratka](#globální-zkratka)
- [Odinstalace](#odinstalace)

---

## Funkce

- **Globální zkratka** — otevře overlay panel s obsahem schránky odkudkoli (výchozí: Cmd+Shift+Space)
- **Text i obrázky** — čte text ze schránky nebo extrahuje text z obrázků přes Apple Vision OCR
- **Více providerů** — OpenAI, Anthropic, Azure OpenAI, vlastní OpenAI-compatible endpoint (Ollama, LM Studio, …)
- **Vlastní akce** — libovolný počet akcí se systémovými prompty; každá má vlastní provider, model, teplotu a limit tokenů
- **Správa akcí** — zapínání/vypínání, drag & drop řazení, mazání s potvrzením
- **Vlastní modely** — každý provider podporuje zadání libovolného modelu mimo předdefinovaný seznam
- **Spuštění při přihlášení** — volitelná integrace se Service Management
- **Automatické zkopírování a zavření** — globální přepínač; po dokončení akce se výsledek zkopíruje do schránky a overlay se sám zavře
- **Bezpečné uložení klíčů** — API klíče jsou v macOS Keychain, nikoli v konfiguračním souboru

---

## Požadavky

- macOS 15.0 (Sequoia) nebo novější
- Xcode 16+ (pro sestavení ze zdrojového kódu)
- API klíč alespoň jednoho podporovaného providera

---

## Instalace a sestavení

```bash
# Naklonuj repozitář
git clone <repo-url>
cd JZLLMContext

# Vygeneruj Xcode projekt
brew install xcodegen
xcodegen generate

# Sestav aplikaci
xcodebuild -scheme JZLLMContext -configuration Debug build
```

Sestavená aplikace se nachází v:

```
~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug/JZLLMContext.app
```

Spuštění:

```bash
open ~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug/JZLLMContext.app
```

### Ikony aplikace

Aplikace hledá tyto PNG soubory v katalogu assetů. Bez nich použije systémový symbol hvězdičky jako zálohu.

| Soubor | Rozměr | Použití |
|--------|--------|---------|
| `Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png` | 18×18 px, černobílá | Ikona v menu baru (template) |
| `Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png` | 36×36 px, černobílá | Ikona v menu baru @2x |
| `Assets.xcassets/AppColorIcon.imageset/AppColorIcon.png` | min. 64×64 px, barevná | Ikona v dropdown menu |

---

## Uživatelská příručka

### Základní použití

1. Označ a zkopíruj text (nebo zkopíruj obrázek s textem do schránky)
2. Stiskni **Cmd+Shift+Space** odkudkoli
3. V overlay panelu uvidíš náhled obsahu schránky a seznam akcí
4. Klikni na tlačítko akce — výsledek se zobrazí pod akcemi
5. Klikni na **Zkopírovat** (nebo **Cmd+C** přímo v panelu) a výsledek máš zpět ve schránce
6. Panel zavřeš klávesou **Escape** nebo tlačítkem ×

### Menu bar

Aplikace žije v menu baru (LSUIElement — nevytváří ikonu v Docku).

- **Levé kliknutí** — otevře overlay panel (stejně jako zkratka)
- **Pravé kliknutí** nebo **Option + levé kliknutí** — otevře dropdown menu s možnostmi:
  - O aplikaci JZLLMContext
  - Nastavení… (nebo Cmd+,)
  - Ukončit JZLLMContext

V hlavičce dropdown menu je zobrazena aktuální globální zkratka.

### Overlay panel

Panel je plovoucí (HUD) okno, které se zobrazuje nad ostatními aplikacemi a je viditelné na všech plochách a ve fullscreen režimu.

- **Náhled schránky** — zobrazí prvních 300 znaků obsahu (text nebo informaci o OCR)
  - Ikona `doc.on.clipboard` = přímý text
  - Ikona `doc.viewfinder` = obsah pochází z OCR obrázku
- **Tlačítka akcí** — jen povolené akce
  - Spinner = akce právě běží
  - Trojúhelník ⚠ = chybí API klíč pro daný provider
  - Šipka → = akce je připravena
- **Oblast výsledku** — zobrazí se po dokončení akce; text lze vybrat myší
- **Tlačítka po dokončení**:
  - **Zkopírovat** / **Zkopírováno ✓** — zkopíruje výsledek do schránky
  - **Zavřít** — skryje panel
  - Při chybě: **Zkusit znovu** a případně **Otevřít nastavení** (chybí API klíč)

Nové stisknutí zkratky při otevřeném panelu znovu načte obsah schránky a resetuje výsledek.

### Nastavení – Obecné

- **Spustit při přihlášení** — registruje/odregistruje aplikaci pomocí Service Management. Přepnutí se okamžitě projeví bez restartu.
- **Po dokončení zkopírovat a zavřít** — globální přepínač; po úspěšném dokončení jakékoli akce se výsledek automaticky zkopíruje do schránky a overlay se zavře. Ekvivalent kliknutí na „Zkopírovat" + křížek bez nutnosti interakce.

### Nastavení – Akce

Správa akcí, které se zobrazují v overlay panelu.

- **Přidání akce** — tlačítko „Přidat akci" přidá novou akci s výchozím názvem, prázdným promptem a modelem gpt-4o
- **Zapnutí/vypnutí** — přepínač vlevo od názvu; vypnuté akce se nezobrazují v overlay panelu
- **Název** — textové pole s názvem zobrazeným na tlačítku v overlay panelu
- **Systémový prompt** — instrukce pro LLM; text se posílá jako `system` message, obsah schránky jako `user` message
- **Provider a model** — výběr providera a modelu (viz [Vlastní modely](#vlastní-modely))
- **Teplota** — slider 0.0–2.0 (krok 0.1); výchozí 0.7
  - Pro Anthropic se hodnota ořízne na max. 1.0 (limit API)
- **Max. tokenů** — stepper 256–32 000 (krok 256); výchozí 4 096
- **Přesouvání** — drag & drop pro změnu pořadí akcí
- **Mazání** — tlačítko koše otevře potvrzovací dialog; akce se nedá vrátit zpět

Všechny změny se ukládají okamžitě po každé úpravě.

### Nastavení – Providery

Záložka pro správu API klíčů a konfigurace providerů.

**OpenAI**
- Pole pro API klíč (SecureField) + tlačítko Uložit
- Klíč se uloží do macOS Keychain

**Anthropic**
- Pole pro API klíč + tlačítko Uložit

**Azure OpenAI**
- API klíč
- Endpoint URL — celá URL prostředí Azure (např. `https://mojeresurce.openai.azure.com`)
- Deployment name — název deployment v Azure portálu
- Endpoint a deployment name se ukládají v konfiguračním souboru (ne v Keychain)

**Vlastní OpenAI-compatible**
- Base URL — URL kompatibilního endpointu (např. `http://localhost:11434/v1` pro Ollama)
- API klíč — volitelné; pro lokální modely lze nechat prázdné
- Base URL se ukládá v konfiguračním souboru

Po kliknutí na **Uložit** se u každého providera zobrazí ikona `✓` (zelená) nebo `✗` (červená) podle výsledku uložení do Keychain.

### Nastavení – Zkratka

Přizpůsobení globální klávesové zkratky.

1. Klikni na pole se zkratkou — pole se přepne do režimu záznamu a zobrazí „Stiskni zkratku…"
2. Stiskni požadovanou kombinaci (musí obsahovat alespoň jeden modifikátor)
3. Zkratka se okamžitě uloží a znovu zaregistruje
4. Kliknutím znovu na pole zrušíš záznam bez uložení

Aktuální zkratka je zobrazena i v hlavičce dropdown menu v menu baru.

---

## Vlastní modely

Každý provider nabízí předdefinovaný seznam modelů a možnost zadat libovolný model:

| Provider | Předdefinované modely |
|----------|----------------------|
| OpenAI | gpt-4o, gpt-4o-mini, o4-mini, o3 |
| Anthropic | claude-sonnet-4.6, claude-opus-4.7, claude-haiku-4.5 |
| Azure OpenAI | gpt-4o |
| Vlastní | — (jen ruční zadání) |

Výběr vlastního modelu:
1. V nastavení akce otevři výběr modelu
2. Vyber „Vlastní model…" na konci seznamu
3. Zobrazí se textové pole — zadej přesný identifikátor modelu (např. `gpt-4.5-preview`, `claude-opus-4-7-20260131`)
4. Hodnota se uloží okamžitě

Pro provider **Vlastní** (vlastní OpenAI-compatible endpoint) se pole pro model zobrazuje rovnou bez výběru ze seznamu.

---

## Vlastní OpenAI-compatible provider

Aplikace podporuje libovolný server kompatibilní s OpenAI Chat Completions API (`/chat/completions`). Typické použití:

**Ollama (lokální modely)**
```
Base URL: http://localhost:11434/v1
API klíč: (nechat prázdné)
Model: llama3.2, mistral, ...
```

**LM Studio**
```
Base URL: http://localhost:1234/v1
API klíč: (nechat prázdné nebo libovolný řetězec)
Model: (název modelu načteného v LM Studio)
```

**Jiný cloud provider**
```
Base URL: https://api.together.xyz/v1
API klíč: <tvůj klíč>
Model: meta-llama/Llama-3.2-90B-Vision-Instruct-Turbo
```

---

## Technický popis

### Architektura

```
AppDelegate
  ├── HotkeyManager          – registrace globální zkratky přes Carbon API
  ├── OverlayWindowController – správa NSPanel (vytvořen jednou, opakovaně zobrazován)
  │     └── OverlayView       – SwiftUI UI overlay panelu
  │           └── ActionEngine – asynchronní volání LLM (ObservableObject)
  ├── SettingsWindowController – NSWindow + NSHostingView(SettingsView)
  └── AboutWindowController   – NSWindow + NSHostingView(AboutView)

ConfigStore (singleton)       – čtení/zápis config.json
KeychainStore                 – ukládání API klíčů do macOS Keychain
ContextResolver               – čtení NSPasteboard + Vision OCR
ProviderFactory               – vytváření LLMProvider podle konfigurace akce
  ├── OpenAIProvider           – OpenAI + Azure OpenAI + vlastní endpoint
  └── AnthropicProvider        – Anthropic Claude
```

Overlay panel se vytvoří jednou při prvním vyvolání a při dalších stisknutích zkratky se pouze znovu zobrazí a aktualizuje obsah schránky přes `OverlayState.refreshID` (UUID trigger). Tím se předchází problémům s macOS window restoration a vícenásobnými okny.

### Ukládání konfigurace

Konfigurace (akce, zkratka, Azure/Custom URL) se ukládá do JSON souboru:

```
~/Library/Application Support/JZLLMContext/config.json
```

Soubor se zapíše atomicky (přes dočasný soubor) po každé změně v nastavení. Při prvním spuštění se vytvoří s výchozí konfigurací obsahující 5 předpřipravených akcí.

API klíče se **neukládají** do konfiguračního souboru — viz níže.

### Ukládání API klíčů

API klíče jsou uloženy v macOS Keychain pod service `com.jz.JZLLMContext` s těmito account klíči:

| Provider | Keychain account |
|----------|-----------------|
| OpenAI | `jzllmcontext.openai.apikey` |
| Anthropic | `jzllmcontext.anthropic.apikey` |
| Azure OpenAI | `jzllmcontext.azure_openai.apikey` |
| Vlastní | `jzllmcontext.custom_openai.apikey` |

### Struktura konfiguračního souboru

```json
{
  "actions": [
    {
      "enabled": true,
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "maxTokens": 4096,
      "model": "gpt-4o",
      "name": "Název akce",
      "provider": "openai",
      "systemPrompt": "Systémový prompt…",
      "temperature": 0.7
    }
  ],
  "azureDeploymentName": "muj-deployment",
  "azureEndpoint": "https://...",
  "customOpenAIBaseURL": "http://localhost:11434/v1",
  "autoCopyAndClose": false,
  "hotkeyKeyCode": 49,
  "hotkeyModifiers": 768,
  "schemaVersion": 1
}
```

Hodnoty `hotkeyKeyCode` a `hotkeyModifiers` jsou kódy Carbon API. Výchozí zkratka Cmd+Shift+Space odpovídá `keyCode: 49` (Space), `modifiers: 768` (cmdKey | shiftKey).

Provider se ukládá jako string: `"openai"`, `"anthropic"`, `"azure_openai"`, `"custom_openai"`.

### Providery a jejich limity

| Provider | Endpoint | Teplota | Poznámka |
|----------|----------|---------|----------|
| OpenAI | `https://api.openai.com/v1/chat/completions` | 0.0–2.0 | Standard Bearer auth |
| Anthropic | `https://api.anthropic.com/v1/messages` | 0.0–1.0 | Teplota oříznutá na 1.0; header `x-api-key` + `anthropic-version: 2023-06-01` |
| Azure OpenAI | `{endpoint}/openai/deployments/{deployment}/chat/completions` | 0.0–2.0 | Stejná implementace jako OpenAI, jiná base URL |
| Vlastní | `{customBaseURL}/chat/completions` | 0.0–2.0 | OpenAI Chat Completions protokol; API klíč volitelný |

Timeout všech HTTP požadavků: **30 sekund**.

### OCR pipeline

Při aktivaci overlay panelu aplikace zkontroluje obsah schránky:

1. Pokud schránka obsahuje text → použije se přímo
2. Pokud schránka obsahuje obrázek (bez textu) → spustí se Apple Vision OCR:
   - `VNRecognizeTextRequest` s `recognitionLevel: .accurate`
   - Výsledné bloky jsou seřazeny od shora dolů (sestupně dle `boundingBox.origin.y`)
   - Bloky jsou spojeny oddělovačem `\n`
3. Pokud je schránka prázdná → zobrazí se chybová zpráva

Při detekci obrázku se v overlay zobrazí speciální tlačítko „Rozpoznat text z obrázku (OCR)", které zobrazí extrahovaný text bez volání LLM.

### Globální zkratka

Zkratka je registrována přes Carbon `RegisterEventHotKey` s identifikátorem `JZLC`. Při změně zkratky v nastavení se provede `unregister()` → `register()` se novými hodnotami. Změna se šíří přes `NotificationCenter` (`hotkeyDidChange`).

Aplikace je typu LSUIElement (agent) — nemá ikonu v Docku a nevytváří standardní aplikační menu, proto je okno nastavení spravováno ručně přes `NSWindowController` v `AppDelegate`.


### ToDo

- Streaming odpovědí — teď aplikace čeká až 30 s na celý výsledek; obě API (OpenAI i Anthropic) streaming podporují, implementace je přímočará. Největší zlepšení UX ze všeho na seznamu.
- Tlačítko Zrušit v overlay — ActionEngine.cancel() existuje, ale chybí mu UI. Stačí přidat tlačítko vedle spinneru.
- Klávesové zkratky pro akce — stisknutí 1–9 v overlay panelu spustí příslušnou akci bez myši. Přidat .onKeyPress do OverlayView.
- Export / import akcí — uložit/načíst vybrané akce jako JSON soubor. Užitečné pro sdílení konfigurací nebo zálohování. Action je už Codable, takže to je triviální.
- Proměnné v systémových promptech — {{datum}}, {{jazyk}} apod.; jednoduché string interpolace před odesláním. Dává smysl třeba pro akci "Napiš v jazyce textu".
- Indikátor načítání v menu baru — animovaný symbol nebo ztmavení ikony při aktivním požadavku. Uživatel neví, co se děje, pokud overlay zakryje jiná okna.
- Historie výsledků — záložka nebo dropdown v overlay s posledními N výsledky (session-only, žádná perzistence). Praktické při přepínání mezi více texty.
- Řetězení akcí — tlačítko „Použít výsledek jako vstup" spustí další akci na výstupu předchozí. Příklad: přeložit → přepsat → zkopírovat.
- Doplňkový kontext — volitelné textové pole v overlay pro přidání instrukce nad rámec schránky. Nahradí potřebu udržovat desítky podobných akcí.

---

## Odinstalace

Aplikace nezapisuje do systémových adresářů ani do registru — veškerá data jsou na třech místech.

### Soubory aplikace

| Co | Cesta |
|----|-------|
| Aplikace | tam, kam jsi ji zkopíroval/sestavil, např. `/Applications/JZLLMContext.app` |
| Konfigurační soubor | `~/Library/Application Support/JZLLMContext/config.json` |

Smazání konfiguračního adresáře:

```bash
rm -rf ~/Library/"Application Support"/JZLLMContext
```

### API klíče v Keychain

API klíče jsou uloženy v macOS Keychain pod service `com.jz.JZLLMContext`. Smazání přes terminál:

```bash
security delete-generic-password -s "com.jz.JZLLMContext" -a "jzllmcontext.openai.apikey"
security delete-generic-password -s "com.jz.JZLLMContext" -a "jzllmcontext.anthropic.apikey"
security delete-generic-password -s "com.jz.JZLLMContext" -a "jzllmcontext.azure_openai.apikey"
security delete-generic-password -s "com.jz.JZLLMContext" -a "jzllmcontext.custom_openai.apikey"
```

Alternativně v aplikaci **Klíčenka** (Keychain Access): vyhledat `com.jz.JZLLMContext` a smazat nalezené položky.

### Spuštění při přihlášení

Pokud bylo zapnuto „Spustit při přihlášení", odregistruj aplikaci ještě před smazáním (přes Nastavení → Obecné), nebo ručně:

```bash
# Zobrazí stav registrace
sudo launchctl list | grep JZLLMContext
```

macOS by měl registraci smazat automaticky při odstranění `.app` bundlu, ale pokud ne, lze záznam dohledat v `~/Library/LaunchAgents/`.