---
title: JZLLMContext – Projektová specifikace
type: Specification
project: JZLLMContext
platform: macOS
version: "1.1"
created: 2026-04-25
author: Jan / Claude (⚠️)
changes:
  - "1.1: oprava protichůdných požadavků distribuce/notarization; doplněn context capture flow; model selection UX; konfigurovatelné akce; macOS verze; OCR scope"
---

# JZLLMContext – Projektová specifikace

## Obsah

- [[#1. Cíl projektu]]
- [[#2. Scope (MVP)]]
- [[#3. Architektura]]
- [[#4. UX / UI]]
- [[#5. Konfigurace]]
- [[#6. Security model]]
- [[#7. Oprávnění]]
- [[#8. Distribuce]]
- [[#9. Notarization readiness]]
- [[#10. Output behavior]]
- [[#11. Error handling]]
- [[#12. Performance]]
- [[#13. Budoucí rozšíření]]
- [[#14. Technologický stack]]
- [[#15. Rizika]]
- [[#16. MVP checklist]]
- [[#17. Definice úspěchu]]

---

## 1. Cíl projektu

Vytvořit lightweight macOS utilitu umožňující:

- zachytit aktuální kontext (text / obrázek ze schránky)
- vyvolat akce pomocí globální klávesové zkratky
- zpracovat data pomocí LLM (OpenAI / Azure OpenAI / Anthropic)
- zobrazit výsledek uživateli (preview + clipboard)

Utilita je určena pro interní použití malým týmem. Distribuce prvních verzí bez notarizace; architektura musí být připravena na notarizaci od začátku.

---

## 2. Scope (MVP)

### 2.1 Funkční rozsah

- globální hotkey (konfigurovatelný)
- overlay UI (Spotlight-like)
- získání kontextu (viz sekce 3.2 – Context Resolver)
- akce: konfigurovatelné v GUI (viz sekce 5)
- výstup: preview window + copy to clipboard

### 2.2 Mimo scope (MVP)

- plugin systém
- komplexní pipeline editor v UI
- auto-update
- telemetrie
- sandbox režim
- replace selection (nahrazení textu přímo v zdrojové aplikaci)
- Accessibility API fallback
- screenshot OCR

---

## 3. Architektura

### 3.1 High-level

```
Hotkey Trigger
      ↓
Context Resolver
      ↓
Action Engine
      ↓
LLM Provider Layer
      ↓
UI Overlay (Preview + Actions)
```

### 3.2 Komponenty

#### Context Resolver

Clipboard-only přístup pro MVP. Rozhodovací strom:

```
Hotkey spuštěn
      │
      ▼
[1] Clipboard obsahuje text?
      │ ANO → předej text do Action Engine
      │
      ▼
[2] Clipboard obsahuje obrázek?
      │ ANO → Vision OCR (VNRecognizeTextRequest z pasteboard image)
      │        → text → Action Engine
      │
      ▼
[3] Clipboard prázdný nebo nekompatibilní typ
      └→ zobraz chybu v overlay: „Zkopíruj text nebo obrázek do schránky (⌘C)"
```

**Poznámky k implementaci:**

- `VNRecognizeTextRequest` s `recognitionLevel: .accurate`
- macOS 15: automatická detekce jazyka, není třeba specifikovat
- Výstup: řetězec z `VNRecognizedTextObservation` seřazených dle `boundingBox.origin.y`
- OCR probíhá z `NSPasteboard` image — nevyžaduje žádná systémová oprávnění

Accessibility API a screenshot OCR jsou odloženy na v2.

#### Action Engine

Pipeline model s kroky:

1. **extract** — získání textu z Context Resolver
2. **transform** — aplikace promptu + volání LLM providera
3. **output** — předání výsledku do UI Overlay

#### Provider Layer

Abstrakce nad třemi providery:

| Provider     | Typ endpointu                | Poznámka                                |
|--------------|------------------------------|-----------------------------------------|
| OpenAI       | REST API (api.openai.com)    | standardní                              |
| Azure OpenAI | REST API (vlastní endpoint)  | vyžaduje endpoint URL + deployment name |
| Anthropic    | REST API (api.anthropic.com) |                                         |

Model je konfigurovatelný v GUI (viz sekce 5.2).

---

## 4. UX / UI

### 4.1 Interakční model

1. Uživatel zkopíruje obsah (⌘C) ve zdrojové aplikaci
2. Stiskne globální hotkey → otevře se overlay
3. Vybere akci z dropdown/seznamu
4. Overlay zobrazí preview výsledku
5. Uživatel zvolí: **Copy** nebo **Zavřít**

### 4.2 UI principy

- SwiftUI + NSPanel (floating, non-activating panel)
- NSPanel: `canBecomeKeyWindow = true` pro keyboard-first navigaci, ale nesmí aktivovat aplikaci (`NSPanel` s `NSWindowStyleMask.nonactivatingPanel`)
- Keyboard-first navigace (Tab, Enter, Escape)
- Minimalistický design — macOS native feel
- Overlay se zavře klávesou Escape nebo kliknutím mimo

### 4.3 Model selection UI

Dropdown se třemi úrovněmi:

```
Provider (OpenAI / Azure OpenAI / Anthropic)
  └─ Model (dropdown)
       ├─ gpt-4o          [Doporučeno] Rychlý, vyvážený výkon
       ├─ gpt-4o-mini     Ekonomická varianta
       ├─ o3-mini         Reasoning úlohy
       ├─ claude-sonnet-4-20250514  [Doporučeno] Vyvážený výkon
       ├─ claude-haiku-4-5-20251001 Rychlý, ekonomický
       └─ ... (rozšiřitelný seznam)
```

- Každá přednastavená varianta obsahuje: identifikátor modelu, zobrazovaný název, krátký popis, volitelně badge „Doporučeno"
- Uživatel může zadat vlastní model ID (textové pole jako fallback)
- Konfigurace se ukládá per-akce (každá akce může mít jiný model/provider)

---

## 5. Konfigurace

### 5.1 Principy

- Správa výhradně přes GUI (žádná ruční editace JSON)
- JSON jako storage a formát pro export/import
- Umístění: `~/Library/Application Support/JZLLMContext/config.json`
- Verze schématu: pole `schemaVersion` v JSON (pro budoucí migraci)

### 5.2 Konfigurovatelné prvky

| Prvek            | Popis                                            |
|------------------|--------------------------------------------------|
| Hotkey           | Globální klávesová zkratka                       |
| Akce             | Seznam akcí (název, prompt, provider, model)     |
| Systémový prompt | Per-akce, editovatelný v GUI                     |
| Provider mapping | API klíč uložen v Keychain, v JSON jen reference |
| Endpoint URL     | Pro Azure OpenAI (vlastní endpoint + deployment) |

### 5.3 Schéma akce (příklad)

```json
{
  "id": "uuid",
  "name": "Přeložit do češtiny",
  "systemPrompt": "Přelož následující text do češtiny. Odpověz pouze překladem.",
  "provider": "openai",
  "model": "gpt-4o",
  "enabled": true
}
```

---

## 6. Security model

### 6.1 Secrets

- API klíče uloženy výhradně v macOS Keychain (`SecItemAdd`)
- V `config.json` pouze reference (např. `"keychainRef": "jzllmcontext.openai.apikey"`)
- Žádné API klíče v logách, schránce ani jiných persistentních úložištích

### 6.2 Data handling

- Data odesílána LLM providerovi pouze při spuštění akce uživatelem
- Žádné persistentní ukládání vstupů ani výstupů
- Výsledky LLM žijí pouze v paměti do uzavření overlay

### 6.3 Logging

- Technické logy (chyby, timeouty) bez obsahu vstupů/výstupů
- Uložení: `~/Library/Logs/JZLLMContext/`
- Volitelně vypnutelné v konfiguraci

---

## 7. Oprávnění

Pro MVP clipboard-only přístup nevyžaduje žádná systémová oprávnění.

| Oprávnění        | Kdy potřeba             | Verze |
|------------------|-------------------------|-------|
| Accessibility    | AXSelectedText fallback | v2    |
| Screen Recording | Screenshot OCR          | v2    |

`Info.plist` musí obsahovat příslušné `NSUsageDescription` klíče pro budoucí oprávnění — i když pro MVP nejsou aktivní, zajistí notarization readiness.

---

## 8. Distribuce

### 8.1 MVP (v1.x)

- Formát: DMG (primární), ZIP (fallback)
- Aplikace: nepodepsaná, nenotarizovaná
- **Důsledek pro uživatele:** při prvním spuštění nutné obejít Gatekeeper:
  - buď `xattr -d com.apple.quarantine JZLLMContext.app`
  - nebo pravý klik → Otevřít → Otevřít

> ⚠️ Toto chování musí být zdokumentováno v README distribuovaném s aplikací.

### 8.2 Budoucnost (v2+)

- Code signing (Developer ID Application)
- Notarizace (`xcrun notarytool`)
- Stapling (`xcrun stapler`)

---

## 9. Notarization readiness (architektonický požadavek od v1)

I pro nenotarizované MVP musí architektura splňovat:

| Požadavek                       | Detail                                                                               |
|---------------------------------|--------------------------------------------------------------------------------------|
| Hardened Runtime                | Zapnout v Xcode: Signing & Capabilities → Hardened Runtime                           |
| Standardní app bundle           | `Contents/MacOS/`, `Contents/Resources/`, `Info.plist`                               |
| Info.plist                      | `CFBundleIdentifier`, `CFBundleVersion`, `NSPrincipalClass`, Usage Description klíče |
| Žádné unsigned embedded binárky | Všechny závislosti jako Swift packages (SPM), ne vložené .dylib                      |
| Entitlements                    | Soubor `.entitlements` s pouze nutnými entitlements                                  |

Hardened Runtime s sebou nenese runtime overhead — jedná se o metadata Mach-O hlavičky.

---

## 10. Output behavior

**Default (MVP):**

- Preview window v overlay
- Tlačítko Copy → zkopíruje výsledek do schránky

**Budoucí:**

- Replace selection (nahrazení textu v zdrojové aplikaci přes Accessibility API)

---

## 11. Error handling

| Chyba                   | Chování                                |
|-------------------------|----------------------------------------|
| Prázdný clipboard       | Zobrazit chybu v overlay s instrukcí   |
| OCR bez výsledku        | Zobrazit chybu: „Text nebyl rozpoznán" |
| LLM timeout             | Zobrazit chybu + tlačítko Retry        |
| LLM API chyba (4xx/5xx) | Zobrazit kód chyby + zprávu z API      |
| Síťová chyba            | Zobrazit chybu + tlačítko Retry        |

Žádné tiché selhání. Každá chyba musí být viditelná v overlay UI.

**Retry politika:** manuální (tlačítko), žádný automatický retry v MVP.

---

## 12. Performance

- Async execution (Swift Concurrency — `async/await`)
- Cancel support (Task cancellation při zavření overlay)
- LLM request timeout: **30 sekund** (konfigurovatelné v budoucí verzi)
- OCR probíhá synchronně před odesláním na LLM (Vision je dostatečně rychlé)

---

## 13. Budoucí rozšíření

- Streaming odpovědí LLM
- Accessibility API fallback pro výběr textu
- Screenshot OCR (Screen Recording oprávnění)
- Replace selection výstup
- Plugin systém
- Advanced pipeline editor
- Auto-update (Sparkle framework)
- Multi-provider fallback

---

## 14. Technologický stack

| Vrstva                | Technologie                                                           |
|-----------------------|-----------------------------------------------------------------------|
| Jazyk                 | Swift 6                                                               |
| UI                    | SwiftUI + AppKit bridge (NSPanel)                                     |
| OCR                   | Vision framework (`VNRecognizeTextRequest`)                           |
| Klávesové zkratky     | Carbon `RegisterEventHotKey` nebo `NSEvent.addGlobalMonitorForEvents` |
| Storage               | JSON (`Codable`)                                                       |
| Secrets               | Security framework (Keychain)                                         |
| Síť                   | `URLSession` (async/await)                                            |
| Dependency management | Swift Package Manager (SPM)                                           |
| Minimální macOS       | **15.0 (Sequoia)**                                                    |

---

## 15. Rizika

| Riziko                                       | Pravděpodobnost | Mitigace                                       |
|----------------------------------------------|-----------------|------------------------------------------------|
| Prázdný clipboard při triggeru               | Střední         | Chybová zpráva s instrukcí                     |
| OCR rozpozná text nepřesně                   | Nízká–střední   | Uživatel vidí preview před copy                |
| UX friction při prvním spuštění (Gatekeeper) | Vysoká          | README s instrukcemi, v2 notarizace            |
| API klíč unikne z Keychain                   | Velmi nízká     | Standardní Keychain API, žádné logování        |
| Nekompatibilita s budoucí notarizací         | Nízká           | Hardened Runtime od v1, SPM bez unsigned dylib |
| LLM provider nedostupný                      | Střední         | Timeout + manuální retry                       |

---

## 16. MVP checklist

- [ ] Globální hotkey funguje (neblokuje zdrojovou aplikaci)
- [ ] Clipboard text capture funguje
- [ ] Clipboard image → OCR funguje
- [ ] Minimálně 2 LLM akce (výchozí: Přeložit, Přepsat)
- [ ] Akce konfigurovatelné v GUI (název, prompt, provider, model)
- [ ] Model selection dropdown s přednastavenými variantami
- [ ] Preview UI v overlay
- [ ] Copy to clipboard z overlay
- [ ] Keychain integrace pro API klíče
- [ ] Chybové stavy zobrazeny v UI (žádné tiché selhání)
- [ ] Hardened Runtime zapnut
- [ ] Info.plist kompletní

---

## 17. Definice úspěchu

| Metrika                                  | Cíl                                               |
|------------------------------------------|---------------------------------------------------|
| Čas od hotkey po zobrazení overlay       | < 300 ms                                          |
| Čas od spuštění akce po preview výsledku | < 5 s (závisí na LLM)                             |
| Úspěšnost capture (text nebo OCR)        | > 85 % běžných use cases                          |
| Kritické UX blokátory                    | 0                                                 |
| První spuštění bez README                | Gatekeeper varování — akceptováno, zdokumentováno |
