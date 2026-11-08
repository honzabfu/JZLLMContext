# JZLLMContext – dokumentace pro vývojáře

Přesunuto z README, aby zůstalo zaměřené na uživatele. Anglická verze: [DEVELOPMENT.md](DEVELOPMENT.md). Pravidla pro programovacího agenta: [`CLAUDE.md`](../CLAUDE.md).

## Instalace a sestavení

```bash
# Naklonuj repozitář
git clone https://github.com/honzabfu/JZLLMContext.git
cd JZLLMContext

# Vygeneruj Xcode projekt
brew install xcodegen
xcodegen generate

# Sestav aplikaci
xcodebuild -scheme JZLLMContext -configuration Debug build

# Spusť unit testy (síť je simulovaná – bez API klíčů a bez nákladů)
xcodebuild test -scheme JZLLMContext -destination 'platform=macOS'

# Volitelně: živé testy proti skutečným API poskytovatelů s API klíči
# a nastavením uloženými v aplikaci (stojí pár centů)
TEST_RUNNER_LIVE_API_TESTS=1 xcodebuild test -scheme JZLLMContext -destination 'platform=macOS' \
  -only-testing:JZLLMContextTests/LiveAPITests
```

Sestavená aplikace se nachází v:

```
~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug/JZLLMContext.app
```

## Ikony aplikace

Aplikace hledá tyto PNG soubory v katalogu assetů. Bez nich použije systémový symbol hvězdičky jako zálohu.

| Soubor | Rozměr | Použití |
|--------|--------|---------|
| `Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png` | 18×18 px, černobílá | Ikona v menu baru (template) |
| `Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png` | 36×36 px, černobílá | Ikona v menu baru @2x |
| `Assets.xcassets/AppColorIcon.imageset/AppColorIcon.png` | min. 64×64 px, barevná | Ikona v dropdown menu |

## Architektura

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
  ├── OpenAIProvider           – OpenAI + Azure OpenAI (2 sloty) + dynamické vlastní endpointy
  └── AnthropicProvider        – Anthropic Claude
```

Overlay panel se vytvoří jednou a opakovaně se používá. Další stisknutí zkratky obnoví obsah schránky, pokud není načtený přetažený soubor; v takovém případě zůstane zachován soubor, běžící akce i výsledek.

Aplikace je typu LSUIElement (agent) – nemá ikonu v Docku a nevytváří standardní aplikační menu, proto je okno nastavení spravováno ručně přes `NSWindowController` v `AppDelegate`.

## OCR pipeline

Při aktivaci overlay panelu aplikace zkontroluje obsah schránky:

1. Nejdříve se načte soubor zkopírovaný ve Finderu; u obrázku se rozpozná text místo použití názvu souboru
2. Jinak se použije zkopírovaný text
3. Jinak se rozpozná text ze zkopírovaného obrázku. Rozpoznávání běží na pozadí; při chybě nebo nenalezení textu se zobrazí chyba
4. Pokud je schránka prázdná → zobrazí se chybová zpráva

## Globální zkratka

Zkratka je registrována přes Carbon `RegisterEventHotKey` s identifikátorem `JZLC`. Při změně se provede `unregister()` → `register()` se novými hodnotami; změna se šíří přes `NotificationCenter` (`hotkeyDidChange`).

---
