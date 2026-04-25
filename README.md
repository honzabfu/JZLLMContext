# JZLLMContext

Utilita pro macOS menu bar, která zpracovává obsah schránky pomocí jazykových modelů. Akce spustíš globální klávesovou zkratkou a výsledek dostaneš okamžitě.

## Funkce

- **Globální zkratka** (Cmd+Shift+Space) — otevře overlay s aktuálním obsahem schránky
- **Text i obrázky** — čte text ze schránky nebo extrahuje text z obrázků přes OCR (framework Vision)
- **Více providerů** — OpenAI, Anthropic, Azure OpenAI
- **Vlastní akce** — definuj vlastní systémové prompty (překlad, přepis, shrnutí, …)
- **Nastavení per akce** — model, teplota, maximální počet tokenů
- **Přesouvání akcí** — změna pořadí přetažením v nastavení

## Požadavky

- macOS 15.0+
- API klíč alespoň jednoho providera (OpenAI, Anthropic nebo Azure OpenAI)

## Instalace

### Sestavení ze zdrojového kódu

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme JZLLMContext -configuration Debug build
```

Sestavená aplikace se nachází v `~/Library/Developer/Xcode/DerivedData/`.

### Spuštění

```bash
open ~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug/JZLLMContext.app
```

### Přidání ikon (volitelné)

Vlož tyto PNG soubory do katalogu assetů:

| Soubor | Popis |
|--------|-------|
| `Sources/JZLLMContext/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png` | Ikona v menu baru, černobílá, 18×18 px |
| `Sources/JZLLMContext/Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png` | Ikona v menu baru @2x, 36×36 px |
| `Sources/JZLLMContext/Resources/Assets.xcassets/AppColorIcon.imageset/AppColorIcon.png` | Barevná ikona aplikace, min. 64×64 px |

Bez těchto souborů aplikace použije jako zálohu systémový symbol hvězdičky.

### Přidání API klíčů

1. Klikni na ikonu v menu baru → **Nastavení…**
2. Přejdi na záložku **Providery**
3. Zadej API klíč a klikni na **Uložit**

## Použití

1. Zkopíruj text nebo obrázek do schránky
2. Stiskni **Cmd+Shift+Space**
3. Klikni na tlačítko akce pro zpracování obsahu
4. Klikni na **Zkopírovat** pro zkopírování výsledku

## Nastavení

Vše v okně **Nastavení…**:

**Záložka Akce** — správa akcí:
- Zapnutí/vypnutí jednotlivých akcí
- Úprava názvu, systémového promptu, providera a modelu
- Nastavení teploty a maximálního počtu tokenů
- Přesouvání přetažením, mazání tlačítkem koše (s potvrzením)

**Záložka Providery** — API klíče a konfigurace Azure

## Architektura

```
AppDelegate               — menu bar, menu, zkratka, okno nastavení
HotkeyManager             — globální zkratka přes Carbon API
OverlayWindowController   — životní cyklus NSPanel, refresh obsahu
OverlayView               — SwiftUI overlay
ActionEngine              — správa asynchronního volání LLM
ContextResolver           — čtení schránky, OCR přes Vision
ConfigStore               — konfigurace v UserDefaults
KeychainStore             — ukládání API klíčů do Keychain
ProviderFactory           — vytváření LLMProvider z konfigurace akce
OpenAIProvider            — OpenAI a Azure OpenAI
AnthropicProvider         — Anthropic Claude
```
