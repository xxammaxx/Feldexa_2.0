# Contract: German Error and Recovery Catalog

**Feature**: `001-scanned-form-workflow` | **Release locale**: `de` only | **Source of truth**: `apps/feldexa_app/lib/l10n/app_de.arb` (keys identical to this catalog)

Every user-facing string is German (FR-090, SC-014). Codes are stable machine identifiers used by tests, diagnostics, and code; **codes never appear in the UI**. Placeholders use `{name}` and are filled from typed values. Messages must name the actual cause, never invent one, and never claim success before verification.

**Tone rules**
- Address the user as „Sie“.
- State what happened, why (only if known), and what the user can do next.
- Never blame the user, never expose file paths, never include document content, never include internal codes.
- Do not say „passwortgeschützt“ unless encryption was positively detected (FR-007).
- Do not claim data is intact when it is unreadable.
- Keep primary messages ≤ 2 sentences; recovery guidance may be a third sentence.

---

## 1. Import

| Code | Condition | German message | Recovery guidance |
| --- | --- | --- | --- |
| `IMP-001` | PDF positively identified as password-protected/encrypted | „Diese PDF-Datei ist passwortgeschützt. Feldexa kann geschützte Dateien nicht öffnen, und Ihr Passwort wird weder abgefragt noch gespeichert.“ | „Bitte entfernen Sie den Schutz in einem PDF-Programm, das Sie dafür verwenden dürfen, und importieren Sie die Datei erneut.“ |
| `IMP-002` | File unreadable, truncated, or damaged beyond use | „Die Datei konnte nicht gelesen werden. Sie ist möglicherweise unvollständig oder beschädigt.“ | „Bitte öffnen Sie die Datei in einem PDF-Programm, speichern Sie sie erneut und versuchen Sie es noch einmal.“ |
| `IMP-003` | File missing or no longer accessible | „Die ausgewählte Datei ist nicht mehr verfügbar. Möglicherweise wurde sie verschoben, umbenannt oder gelöscht.“ | „Bitte wählen Sie die Datei erneut aus.“ |
| `IMP-004` | Not a PDF or unsupported PDF structure | „Diese Datei ist kein unterstütztes PDF. Feldexa kann nur PDF-Dokumente importieren.“ | „Bitte wählen Sie eine PDF-Datei aus.“ |
| `IMP-005` | Failure reason cannot be determined | „Die Datei konnte nicht gelesen werden. Die Ursache lässt sich nicht sicher feststellen.“ | „Bitte versuchen Sie es erneut. Wenn das Problem bleibt, öffnen und speichern Sie die Datei in einem PDF-Programm.“ |
| `IMP-006` | Some pages unreadable, others usable | „Einige Seiten konnten nicht gelesen werden: {pages}. Die übrigen Seiten sind nutzbar. Ein Export des vollständigen Dokuments ist dadurch beeinträchtigt.“ | „Sie können die betroffenen Seiten prüfen und das Dokument trotzdem weiterbearbeiten.“ |
| `IMP-007` | File exceeds 80 MiB | „Die Datei ist zu groß. Feldexa kann PDF-Dateien bis 80 MiB (83.886.080 Bytes) importieren.“ | „Bitte verkleinern Sie die Datei, zum Beispiel durch eine niedrigere Scan-Auflösung, und importieren Sie sie erneut.“ |
| `IMP-000` | User cancelled the picker | *(no message; return to previous screen)* | — |

Notes:
- `IMP-006` is a warning attached to a **successful** import; the affected pages are marked in the page strip.
- The import rejection screen must not create or show a document entry (FR-009).

---

## 2. Page rendering and recognition

| Code | Condition | German message | Recovery guidance |
| --- | --- | --- | --- |
| `PAGE-001` | Page cannot be rendered | „Seite {page} kann nicht angezeigt werden. Die übrigen Seiten bleiben verfügbar.“ | „Sie können auf dieser Seite trotzdem Felder setzen; der Export bleibt eingeschränkt.“ |
| `REC-001` | OCR engine unavailable on this device | *(not shown as an error)* „Die Texterkennung ist auf diesem Gerät nicht verfügbar. Feldexa erkennt Felder nur anhand des Seitenaufbaus.“ | „Sie können Felder jederzeit selbst ergänzen.“ |
| `REC-002` | Detection failed for a page | „Die Felderkennung auf Seite {page} ist fehlgeschlagen. Bereits erkannte Seiten bleiben unverändert.“ | „Bitte ergänzen Sie fehlende Felder auf dieser Seite selbst oder versuchen Sie es erneut.“ |
| `REC-003` | Page structure unsupported/unreadable | „Seite {page} konnte nicht ausgewertet werden. Der Seitenaufbau ist möglicherweise beschädigt.“ | „Sie können die Seite weiter anzeigen und Felder manuell hinzufügen.“ |
| `REC-004` | Detection cancelled | *(no message)* | — |

No recognition surface may state or imply completeness (FR-085): the summary uses „Vorschläge“, „unsicher“ and „bestätigt“, never „vollständig erkannt“ or „fehlerfrei“.

---

## 3. Saving, durability, and recovery

| Code | Condition | German message | Recovery guidance |
| --- | --- | --- | --- |
| `SAVE-001` | Storage full / quota exceeded | „Der Speicherplatz reicht nicht aus. Der letzte gespeicherte Stand ist erhalten; die neuesten Änderungen sind noch nicht dauerhaft gespeichert.“ | „Bitte geben Sie Speicherplatz frei und versuchen Sie es erneut. Feldexa löscht keine Ihrer Dokumente.“ |
| `SAVE-002` | Key material unavailable/invalidated | „Die gespeicherten Daten können nicht entschlüsselt werden, weil der Schlüssel dieses Geräts nicht mehr verfügbar ist. Dieses Dokument kann nicht geöffnet werden. Andere Dokumente und Vorlagen sind davon nicht betroffen.“ | „Eine Wiederherstellung ist nicht möglich. Bitte wenden Sie sich an den Gerätehersteller, wenn der Schlüssel durch eine Zurücksetzung verloren gegangen ist.“ |
| `SAVE-003` | Write failed or stored data corrupted | „Speichern ist fehlgeschlagen. Der zuletzt erfolgreich gespeicherte Stand bleibt erhalten.“ | „Bitte versuchen Sie es erneut. Wenn der Fehler bleibt, prüfen Sie den freien Speicherplatz.“ |
| `SAVE-004` | Recovery fell back to older revision | „Feldexa hat einen älteren gespeicherten Stand wiederhergestellt, weil der neueste Stand nicht lesbar war. Änderungen seit diesem Stand können verloren sein.“ | „Bitte prüfen Sie das Dokument und speichern Sie es erneut.“ |
| `SAVE-005` | Data written by a newer app version | „Dieses Dokument wurde mit einer neueren Version von Feldexa gespeichert. Bitte aktualisieren Sie die App, um es zu öffnen. Die Daten bleiben unverändert.“ | „Öffnen Sie das Dokument erst nach dem Update wieder.“ |
| `SAVE-006` | Concurrent save conflict | *(internal; no user message)* Retry automatically once; if it persists: „Das Speichern konnte nicht abgeschlossen werden. Bitte versuchen Sie es erneut.“ | — |
| `SAVE-007` | Invalid data rejected (oversized/invalid payload) | „Die Änderung konnte nicht gespeichert werden, weil die Daten ungültig sind. Der letzte gespeicherte Stand bleibt erhalten.“ | „Bitte prüfen Sie sehr lange Eingaben und versuchen Sie es erneut.“ |

**Durability labels** (must be used consistently, FR-046):

| State | German label | Semantics |
| --- | --- | --- |
| `clean` | „Gespeichert“ | no changes since verified commit |
| `saving` | „Wird gespeichert …“ | commit in progress; not yet durable |
| `saved` | „Gespeichert um {time}“ | verified durable commit |
| `unsaved` | „Nicht gespeichert – Änderungen sind gefährdet“ | in-memory changes only |
| `saveFailed` | „Speichern fehlgeschlagen – letzter gespeicherter Stand: {time}“ | failure with preserved prior state |
| `recoveryFallback` | „Älterer Stand wiederhergestellt“ | fallback after corruption |

Forbidden: „Alles gespeichert“, „Sicher gespeichert“, or any wording implying durability for unsaved edits.

**Pre-emptive key/backup disclosure** (`PRIV-001`, shown in the first-run help and before the first save):
„Ihre Dokumente werden nur auf diesem Gerät und mit einem Schlüssel gespeichert, der an dieses Gerät gebunden ist. Sicherungskopien der App-Daten sind nicht möglich. Wenn der Schlüssel verloren geht – zum Beispiel durch Zurücksetzen des Geräts –, können die betroffenen Dokumente nicht wiederhergestellt werden. Andere Dokumente bleiben unabhängig davon nutzbar.“

---

## 4. Export and delivery

| Code | Condition | German message | Recovery guidance |
| --- | --- | --- | --- |
| `EXP-001` | Content would be clipped/overflow | „Der Export wurde gestoppt, weil der Inhalt in {count} Feld/Feldern nicht vollständig Platz hat: {fields}. Es wurde keine PDF-Datei erstellt.“ | „Bitte kürzen Sie den Text oder vergrößern Sie die betroffenen Felder und starten Sie den Export erneut.“ |
| `EXP-002` | Export failed/interrupted | „Der Export ist fehlgeschlagen. Es wurde keine gültige PDF-Datei erstellt. Ihr Dokument ist unverändert.“ | „Bitte prüfen Sie den freien Speicherplatz und versuchen Sie es erneut.“ |
| `EXP-003` | Field geometry outside page | „Der Export wurde gestoppt, weil mindestens ein Feld außerhalb der Seite liegt: {fields}. Es wurde keine PDF-Datei erstellt.“ | „Bitte verschieben Sie die betroffenen Felder auf die Seite und versuchen Sie es erneut.“ |
| `EXP-004` | Character not renderable | „Der Export wurde gestoppt, weil ein Zeichen nicht dargestellt werden kann: {fields}. Es wurde keine PDF-Datei erstellt.“ | „Bitte entfernen Sie das betroffene Zeichen oder ersetzen Sie es und versuchen Sie es erneut.“ |
| `EXP-005` | Stored source unreadable | „Der Export ist nicht möglich, weil die gespeicherte Originaldatei nicht mehr gelesen werden kann. Ihr bearbeitetes Dokument bleibt erhalten.“ | „Bitte importieren Sie das Original erneut und übertragen Sie Ihre Angaben.“ |
| `EXP-006` | A page cannot be copied | „Der Export wurde gestoppt, weil Seite {page} nicht übernommen werden kann. Es wurde keine PDF-Datei erstellt. Seiten werden nicht stillschweigend weggelassen.“ | „Bitte prüfen Sie das Original oder importieren Sie es erneut. Andere Seiten und Ihre Eingaben bleiben erhalten.“ |
| `SAVE-001` | No space during export | „Der Speicherplatz reicht für den Export nicht aus. Es wurde keine gültige PDF-Datei erstellt.“ | „Bitte geben Sie Speicherplatz frei und versuchen Sie es erneut.“ |
| `DEL-001` | Delivery cancelled by user | *(no message)* | — |

**Pre-export information** (empty fields: not blocking; unresolved suggestions: provisional pending owner decision OD-1, see `export-plan.md` §3.4): „{empty} Felder sind noch leer. Leere Felder werden nicht ausgefüllt, der Export bleibt möglich.“ and „{count} Vorschläge sind noch nicht geprüft. Sie werden nicht in die PDF-Datei übernommen.“

**Export success**: „Die PDF-Datei ist fertig und wurde geprüft. Sie können sie ansehen, speichern, teilen oder drucken.“ Never „garantiert korrekt“.

**Preview footer**: the in-app preview shows „Vorschau der erzeugten PDF-Datei“ and, only in development/Web, „SIMULATED“.

---

## 5. Templates

| Code | Condition | German message | Recovery guidance |
| --- | --- | --- | --- |
| `TPL-001` | Template creation impossible (no confirmed fields or source unreadable) | „Eine Vorlage kann nicht erstellt werden, weil noch keine Felder bestätigt sind oder die Originalseiten nicht lesbar sind.“ | „Bitte prüfen und bestätigen Sie zuerst die Felder.“ |
| `TPL-002` | Template save failed | „Die Vorlage konnte nicht gespeichert werden. Bereits vorhandene Vorlagenversionen bleiben unverändert.“ | „Bitte prüfen Sie den freien Speicherplatz und versuchen Sie es erneut.“ |
| `TPL-003` | Template opened for editing contains values (internal invariant) | „Die Vorlage konnte nicht geöffnet werden, weil sie unerwartete Eingaben enthält. Es wurden keine Daten geändert.“ | „Bitte versuchen Sie es erneut oder erstellen Sie die Vorlage neu.“ |

**Template labels**: „Als Vorlage speichern“, „Vorlage“, „Vorlagenversion {n} vom {date}“, „Neue Version gespeichert“. Template editor hint: „In einer Vorlage werden nur Felder und Seiten gespeichert – keine Eingaben und keine Unterschriften.“

---

## 6. Date, number, and field input

| Code | Condition | German message | Recovery guidance |
| --- | --- | --- | --- |
| `DATE-001` | Malformed date | „Bitte geben Sie ein gültiges Datum im Format Tag.Monat.Jahr ein, zum Beispiel 31.12.2025.“ | — |
| `DATE-002` | Impossible calendar date (e.g., 31.02.2025) | „Dieses Datum existiert nicht. Bitte geben Sie ein gültiges Datum im Format Tag.Monat.Jahr ein.“ | „Prüfen Sie Tag und Monat.“ |
| `NUM-001` | Invalid number | „Bitte geben Sie eine gültige Zahl ein, zum Beispiel 1234,56.“ | — |
| `FLD-001` | Text longer than field | „Der Text ist länger als das Feld. Er wurde nicht gekürzt. Der Export wird gestoppt, bis der Text gekürzt oder das Feld vergrößert ist.“ | „Bitte kürzen Sie den Text oder vergrößern Sie das Feld.“ |
| `FLD-002` | Incompatible content after type change | „Der bisherige Inhalt passt nicht zum neuen Feldtyp. Er wurde nicht gelöscht und ist weiterhin sichtbar.“ | „Bitte prüfen Sie den Inhalt und übernehmen, ändern oder verwerfen Sie ihn bewusst.“ |
| `FLD-003` | Conflict between suggestions | „Zwei Vorschläge überlappen sich. Bitte entscheiden Sie für jeden Vorschlag einzeln, ob er übernommen wird.“ | — |

---

## 7. Deletion

**Document deletion dialog** (`DEL-002`):
„Möchten Sie „{title}“ wirklich löschen? Gelöscht werden die gespeicherten Seiten, Felder, Eingaben und Unterschriften dieses Dokuments. Andere Dokumente und Vorlagen bleiben erhalten.“

**Template deletion dialog** (`DEL-003`):
„Möchten Sie die Vorlage „{title}“ mit allen Versionen wirklich löschen? Dokumente, die aus dieser Vorlage erstellt wurden, bleiben unverändert und weiterhin nutzbar.“

**After deletion**: „„{title}“ wurde gelöscht. Andere Dokumente und Vorlagen wurden nicht verändert.“

Deletion is never offered as a way to free space automatically (FR-076).

---

## 8. Start area, empty states, and accessibility

| Context | German text |
| --- | --- |
| Start title | „Meine Dokumente“ |
| Documents group | „Dokumente“ |
| Templates group | „Vorlagen“ |
| Empty documents | „Noch keine Dokumente. Importieren Sie eine gescannte PDF-Datei, um zu beginnen.“ |
| Empty templates | „Noch keine Vorlagen. Speichern Sie ein geprüftes Dokument als Vorlage.“ |
| Import action | „PDF importieren“ |
| Status: draft | „In Bearbeitung“ |
| Status: export-ready | „Exportbereit“ |
| Status: unreadable | „Nicht lesbar“ |
| Field count | „{count} Felder, {filled} ausgefüllt“ |
| Last edited | „Zuletzt bearbeitet: {date}“ |
| Review action | „Felder prüfen“ |
| Fill action | „Ausfüllen“ |
| Export action | „PDF exportieren“ |
| Template action | „Als Vorlage speichern“ |
| Save now | „Jetzt speichern“ |
| Unsaved badge | „Nicht gespeichert“ |
| Unsaved risk banner | „Ihre letzten Änderungen sind noch nicht dauerhaft gespeichert. Verlassen Sie die App nicht, bis „Gespeichert“ erscheint.“ |

**Accessibility semantics** (test-asserted):
- Field overlay: „Feld {label}, Typ {type}, Seite {page}, {filled|leer}, {bestätigt|Vorschlag|selbst erstellt}{, Konflikt}{, unsicher}“.
- Suggestion: „Vorschlag für {type} bei {label}, Zuverlässigkeit {percent} Prozent, nicht bestätigt“.
- Checkbox: „Kontrollkästchen {label}, {aktiviert|nicht aktiviert}“.
- Signature: „Unterschriftenfeld {label}, {unterschrieben|nicht unterschrieben}“.
- Page navigation: „Seite {page} von {count}“.
- Zoom: „Vergrößerung {percent} Prozent“.
- The SIMULATED banner: „SIMULATED – Entwicklungsansicht mit simulierten Plattformfunktionen. Keine Android-Prüfung.“

All interactive controls expose a semantic label, role, and action; errors are announced as live regions and never only by color/icon (FR-094).

---

## 9. SIMULATED labeling

| Context | English label (required exact token) | German context line |
| --- | --- | --- |
| Global banner (Web) | `SIMULATED` | „Entwicklungsansicht: Plattformfunktionen sind simuliert. Ergebnisse gelten nicht als Android-Nachweis.“ |
| Log prefix | `[SIMULATED]` | — |
| Simulated export footer | `SIMULATED` | „Simuliertes PDF – kein Produktionsartefakt.“ |
| Test/report field | `evidenceClass: SIMULATED` | — |
| Simulated storage notice | `SIMULATED` | „Simulierter Speicher – keine echte Verschlüsselung.“ |

The token `SIMULATED` is never translated and never hidden. It appears in the interface, logs, and reports (FR-087).

---

## 10. Developer-only codes (never shown to users)

| Code | Meaning |
| --- | --- |
| `SIM-001` | A simulated adapter was registered in a production build |
| `PLT-001` | Capability unsupported on this build target |
| `PLT-002` | Invalid or unsafe identifier rejected |
| `PLT-003` | Invalid channel payload |
| `PLT-004` | Operation cancelled |
| `REC-004` | Detection cancelled |

Developer messages may appear in debug builds only, in English, without document content.

---

## 11. String audit rules

1. Every key in this catalog exists in `app_de.arb`; `flutter gen-l10n` fails the build on missing keys.
2. A test asserts no user-visible string is English (allowlist: `SIMULATED`, `PDF`, `Feldexa`, `Android`, `ML Kit` only if ever shown — it is not).
3. Placeholders must be typed and escaped; no string concatenation for grammar.
4. German quotes are „…“; apostrophes are ’ where typographically appropriate.
5. Error dialogs have one primary action („Verstanden“ / „Erneut versuchen“ / „Speicherplatz prüfen“) and never a destructive default.
6. Messages that mention data safety are reviewed against the actual implementation before release; wording may not exceed the implemented guarantee.
