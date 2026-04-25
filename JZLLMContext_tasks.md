# JZLLMContext – Přehled úkolů (MVP)

> Odvozeno z MVP checklistu (spec v1.1, sekce 16)  
> Datum: 2026-04-25 | Verze: 1.0

---

| ID    | Komponenta         | Popis                                                                          | Priorita | Stav  |
|-------|--------------------|--------------------------------------------------------------------------------|----------|-------|
| T-01  | Hotkey             | Implementovat globální hotkey (neblokuje zdrojovou aplikaci)                   | Vysoká   | TODO  |
| T-02  | Context Resolver   | Clipboard text capture — číst `NSPasteboard`, předat do Action Engine          | Vysoká   | TODO  |
| T-03  | Context Resolver   | Clipboard image → OCR (`VNRecognizeTextRequest`, `recognitionLevel: .accurate`) | Vysoká   | TODO  |
| T-04  | Action Engine      | Implementovat minimálně 2 výchozí akce: „Přeložit do češtiny", „Přepsat"      | Vysoká   | TODO  |
| T-05  | Konfigurace / GUI  | GUI pro správu akcí (název, systémový prompt, provider, model)                 | Vysoká   | TODO  |
| T-06  | UI / Model Select  | Model selection dropdown s přednastavenými variantami a custom ID polem        | Střední  | TODO  |
| T-07  | UI Overlay         | Preview UI v overlay (Spotlight-like NSPanel, SwiftUI)                         | Vysoká   | TODO  |
| T-08  | UI Overlay         | Tlačítko „Copy to clipboard" — zkopíruje výsledek LLM do schránky             | Vysoká   | TODO  |
| T-09  | Security           | Keychain integrace pro ukládání API klíčů (`SecItemAdd`, reference v JSON)     | Vysoká   | TODO  |
| T-10  | Error Handling     | Zobrazit chybové stavy v overlay UI (prázdný clipboard, OCR, LLM, síť)        | Vysoká   | TODO  |
| T-11  | Build / Distribuce | Zapnout Hardened Runtime v Xcode (Signing & Capabilities)                      | Střední  | TODO  |
| T-12  | Build / Distribuce | Zkompletovat `Info.plist` (CFBundleIdentifier, verze, NSUsageDescription klíče)| Střední  | TODO  |

---

## Poznámky

- **Priorita „Vysoká"** = blocker pro MVP release; musí být hotovo před prvním interním nasazením.
- **Priorita „Střední"** = potřebné pro notarization readiness a čistý build; nesmí chybět v release candidate.
- Všechny úkoly jsou zatím ve stavu **TODO** — po zahájení práce aktualizujte na `IN PROGRESS` / `DONE` / `BLOCKED`.
- Úkoly T-11 a T-12 nemají runtime dopad, ale jsou architektonickým požadavkem od v1 (viz spec sekce 9).
