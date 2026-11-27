import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('de')];

  /// Application name, used for the app bar and the browser document title.
  ///
  /// In de, this message translates to:
  /// **'Feldexa'**
  String get appTitle;

  /// Heading of the start area (contracts/error-catalog.de.md §8).
  ///
  /// In de, this message translates to:
  /// **'Meine Dokumente'**
  String get startTitle;

  /// contracts/error-catalog.de.md §8 Startup recovery incomplete: the bounded startup sweep timed out, threw, or returned a degraded result; the shell must not present this as a complete success.
  ///
  /// In de, this message translates to:
  /// **'Die Wiederherstellung beim Start wurde nicht vollständig abgeschlossen. Bitte starten Sie Feldexa erneut.'**
  String get startupRecoveryIncomplete;

  /// contracts/error-catalog.de.md §8 Startup recovery incomplete guidance: recovery guidance for an incomplete startup sweep; states only the contract guarantee that recovery never deletes a visible document or template (contracts/storage-format.md §4).
  ///
  /// In de, this message translates to:
  /// **'Ihre gespeicherten Dokumente und Vorlagen werden dabei nicht gelöscht. Prüfen Sie nach dem Neustart, ob alle Einträge lesbar sind.'**
  String get startupRecoveryIncompleteRecovery;

  /// contracts/error-catalog.de.md §1 IMP-001: PDF positively identified as password-protected/encrypted.
  ///
  /// In de, this message translates to:
  /// **'Diese PDF-Datei ist passwortgeschützt. Feldexa kann geschützte Dateien nicht öffnen, und Ihr Passwort wird weder abgefragt noch gespeichert.'**
  String get imp001;

  /// contracts/error-catalog.de.md §1 IMP-001: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte entfernen Sie den Schutz in einem PDF-Programm, das Sie dafür verwenden dürfen, und importieren Sie die Datei erneut.'**
  String get imp001Recovery;

  /// contracts/error-catalog.de.md §1 IMP-002: File unreadable, truncated, or damaged beyond use.
  ///
  /// In de, this message translates to:
  /// **'Die Datei konnte nicht gelesen werden. Sie ist möglicherweise unvollständig oder beschädigt.'**
  String get imp002;

  /// contracts/error-catalog.de.md §1 IMP-002: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte öffnen Sie die Datei in einem PDF-Programm, speichern Sie sie erneut und versuchen Sie es noch einmal.'**
  String get imp002Recovery;

  /// contracts/error-catalog.de.md §1 IMP-003: File missing or no longer accessible.
  ///
  /// In de, this message translates to:
  /// **'Die ausgewählte Datei ist nicht mehr verfügbar. Möglicherweise wurde sie verschoben, umbenannt oder gelöscht.'**
  String get imp003;

  /// contracts/error-catalog.de.md §1 IMP-003: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte wählen Sie die Datei erneut aus.'**
  String get imp003Recovery;

  /// contracts/error-catalog.de.md §1 IMP-004: Not a PDF or unsupported PDF structure.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ist kein unterstütztes PDF. Feldexa kann nur PDF-Dokumente importieren.'**
  String get imp004;

  /// contracts/error-catalog.de.md §1 IMP-004: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte wählen Sie eine PDF-Datei aus.'**
  String get imp004Recovery;

  /// contracts/error-catalog.de.md §1 IMP-005: Failure reason cannot be determined.
  ///
  /// In de, this message translates to:
  /// **'Die Datei konnte nicht gelesen werden. Die Ursache lässt sich nicht sicher feststellen.'**
  String get imp005;

  /// contracts/error-catalog.de.md §1 IMP-005: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte versuchen Sie es erneut. Wenn das Problem bleibt, öffnen und speichern Sie die Datei in einem PDF-Programm.'**
  String get imp005Recovery;

  /// contracts/error-catalog.de.md §1 IMP-006: Some pages unreadable, others usable.
  ///
  /// In de, this message translates to:
  /// **'Einige Seiten konnten nicht gelesen werden: {pages}. Die übrigen Seiten sind nutzbar. Ein Export des vollständigen Dokuments ist dadurch beeinträchtigt.'**
  String imp006(String pages);

  /// contracts/error-catalog.de.md §1 IMP-006: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Sie können die betroffenen Seiten prüfen und das Dokument trotzdem weiterbearbeiten.'**
  String get imp006Recovery;

  /// contracts/error-catalog.de.md §1 IMP-007: File exceeds 80 MiB.
  ///
  /// In de, this message translates to:
  /// **'Die Datei ist zu groß. Feldexa kann PDF-Dateien bis 80 MiB (83.886.080 Bytes) importieren.'**
  String get imp007;

  /// contracts/error-catalog.de.md §1 IMP-007: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte verkleinern Sie die Datei, zum Beispiel durch eine niedrigere Scan-Auflösung, und importieren Sie sie erneut.'**
  String get imp007Recovery;

  /// contracts/error-catalog.de.md §2 PAGE-001: Page cannot be rendered.
  ///
  /// In de, this message translates to:
  /// **'Seite {page} kann nicht angezeigt werden. Die übrigen Seiten bleiben verfügbar.'**
  String page001(int page);

  /// contracts/error-catalog.de.md §2 PAGE-001: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Sie können auf dieser Seite trotzdem Felder setzen; der Export bleibt eingeschränkt.'**
  String get page001Recovery;

  /// contracts/error-catalog.de.md §2 REC-001: OCR engine unavailable on this device.
  ///
  /// In de, this message translates to:
  /// **'Die Texterkennung ist auf diesem Gerät nicht verfügbar. Feldexa erkennt Felder nur anhand des Seitenaufbaus.'**
  String get rec001;

  /// contracts/error-catalog.de.md §2 REC-001: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Sie können Felder jederzeit selbst ergänzen.'**
  String get rec001Recovery;

  /// contracts/error-catalog.de.md §2 REC-002: Detection failed for a page.
  ///
  /// In de, this message translates to:
  /// **'Die Felderkennung auf Seite {page} ist fehlgeschlagen. Bereits erkannte Seiten bleiben unverändert.'**
  String rec002(int page);

  /// contracts/error-catalog.de.md §2 REC-002: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte ergänzen Sie fehlende Felder auf dieser Seite selbst oder versuchen Sie es erneut.'**
  String get rec002Recovery;

  /// contracts/error-catalog.de.md §2 REC-003: Page structure unsupported/unreadable.
  ///
  /// In de, this message translates to:
  /// **'Seite {page} konnte nicht ausgewertet werden. Der Seitenaufbau ist möglicherweise beschädigt.'**
  String rec003(int page);

  /// contracts/error-catalog.de.md §2 REC-003: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Sie können die Seite weiter anzeigen und Felder manuell hinzufügen.'**
  String get rec003Recovery;

  /// §2 recognition summary label: suggestions are never described as complete (FR-085).
  ///
  /// In de, this message translates to:
  /// **'Vorschläge'**
  String get suggestionsLabel;

  /// Phase B2 review panel empty state: the completed analysis produced no suggestions.
  ///
  /// In de, this message translates to:
  /// **'Für dieses Dokument wurden keine Felder vorgeschlagen.'**
  String get suggestionEmpty;

  /// Phase B2 review panel empty state: every suggestion has been confirmed or rejected.
  ///
  /// In de, this message translates to:
  /// **'Alle Vorschläge wurden geprüft.'**
  String get suggestionAllReviewed;

  /// Phase B2 review panel header: number of suggestions still awaiting a decision.
  ///
  /// In de, this message translates to:
  /// **'{count} offen'**
  String suggestionOpenCount(int count);

  /// Phase B2 review panel header: confirmed machine/user field count after review actions.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, =0{Keine Felder bestätigt} =1{1 Feld bestätigt} other{{count} Felder bestätigt}}'**
  String suggestionFieldCount(int count);

  /// Phase B2 review panel header: resolved suggestion counts after a confirmation or rejection.
  ///
  /// In de, this message translates to:
  /// **'{confirmed} bestätigt, {rejected} abgelehnt'**
  String suggestionReviewProgress(int confirmed, int rejected);

  /// Phase B2 review row fallback label when the suggestion has no credible printed label.
  ///
  /// In de, this message translates to:
  /// **'Feld'**
  String get suggestionRowFallback;

  /// Phase B2 fallback label for a confirmed suggestion without a credible printed label; <n> is the one-based field number.
  ///
  /// In de, this message translates to:
  /// **'Feld {n}'**
  String suggestionFieldLabel(int n);

  /// Phase B2 review row: one-based page number.
  ///
  /// In de, this message translates to:
  /// **'Seite {page}'**
  String suggestionPage(int page);

  /// Phase B2 review row: candidate position in page display points, rounded to the canonical 1/8 pt display grid.
  ///
  /// In de, this message translates to:
  /// **'x {x} pt · y {y} pt'**
  String suggestionPosition(String x, String y);

  /// Phase B2 review row: confidence as an integer percent (never a probability claim).
  ///
  /// In de, this message translates to:
  /// **'Zuverlässigkeit {percent} %'**
  String suggestionConfidence(int percent);

  /// Phase B2 review row: uncertainty marker for confidence below 0.50 (FR-083).
  ///
  /// In de, this message translates to:
  /// **'unsicher'**
  String get suggestionUncertain;

  /// Phase B2 review row: conflict marker when conflictsWith is non-empty (FR-025); both candidates stay resolvable.
  ///
  /// In de, this message translates to:
  /// **'Konflikt'**
  String get suggestionConflict;

  /// Phase B2 German name for FieldType.text.
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get suggestionTypeText;

  /// Phase B2 German name for FieldType.number.
  ///
  /// In de, this message translates to:
  /// **'Zahl'**
  String get suggestionTypeNumber;

  /// Phase B2 German name for FieldType.date.
  ///
  /// In de, this message translates to:
  /// **'Datum'**
  String get suggestionTypeDate;

  /// Phase B2 German name for FieldType.checkbox.
  ///
  /// In de, this message translates to:
  /// **'Kontrollkästchen'**
  String get suggestionTypeCheckbox;

  /// Phase B2 German name for FieldType.multiline.
  ///
  /// In de, this message translates to:
  /// **'Mehrzeiliger Text'**
  String get suggestionTypeMultiline;

  /// Phase B2 German name for FieldType.signature.
  ///
  /// In de, this message translates to:
  /// **'Unterschrift'**
  String get suggestionTypeSignature;

  /// Phase B2 review action: confirm one suggestion (contracts/editor-interactions.md §3).
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get suggestionConfirmAction;

  /// Phase B2 review action: reject one suggestion; reversible with undo (contracts/editor-interactions.md §3).
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get suggestionRejectAction;

  /// Phase B2 review action: undo the most recent reject or untouched confirm (FR-027).
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get suggestionUndoAction;

  /// T068 conflict sheet title: the per-candidate resolution surface for overlapping suggestions (contracts/editor-interactions.md §3, FR-025).
  ///
  /// In de, this message translates to:
  /// **'Konflikt lösen'**
  String get reviewConflictSheetTitle;

  /// T068 conflict sheet explanation: both symmetric candidates remain and each needs an explicit confirm or reject; swiping never resolves a conflict (contracts/recognition-output.md §6, FR-025).
  ///
  /// In de, this message translates to:
  /// **'Beide Vorschläge bleiben erhalten, bis Sie für jeden einzeln entschieden haben. Durch Wischen wird kein Konflikt gelöst.'**
  String get reviewConflictSheetBody;

  /// T068 conflict sheet action: close the sheet without resolving any candidate.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get reviewConflictCloseAction;

  /// T068 candidate state badge: the suggestion still needs an explicit confirm or reject (data-model.md §3.4).
  ///
  /// In de, this message translates to:
  /// **'Offen'**
  String get reviewConflictStateUnresolved;

  /// T068 candidate state badge: the suggestion was confirmed and is shown without resolution actions (data-model.md §3.4).
  ///
  /// In de, this message translates to:
  /// **'Bestätigt'**
  String get reviewConflictStateConfirmed;

  /// T068 candidate state badge: the suggestion was rejected and is shown without resolution actions (data-model.md §3.4).
  ///
  /// In de, this message translates to:
  /// **'Abgelehnt'**
  String get reviewConflictStateRejected;

  /// T068 conflict sheet note: a stale conflict reference, self-only group, or empty group matches no second candidate; the tapped suggestion is still shown and remains individually resolvable.
  ///
  /// In de, this message translates to:
  /// **'Zu diesem Konflikt ist kein zweiter Vorschlag vorhanden. Der angezeigte Vorschlag bleibt einzeln entscheidbar.'**
  String get reviewConflictSingleCandidateNote;

  /// T068 review-panel conflict badge tooltip and semantic hint: opens the per-candidate resolution sheet (contracts/editor-interactions.md §3).
  ///
  /// In de, this message translates to:
  /// **'Konflikt zwischen Vorschlägen. Tippen, um beide Vorschläge einzeln zu entscheiden.'**
  String get reviewConflictBadgeHint;

  /// T073 field-order review list title and editor action tooltip (FR-026; contracts/editor-interactions.md §3).
  ///
  /// In de, this message translates to:
  /// **'Feldreihenfolge'**
  String get fieldOrderTitle;

  /// T073 field-order review list hint: a row tap selects the field, the arrow actions move it (FR-026).
  ///
  /// In de, this message translates to:
  /// **'Tippen Sie ein Feld an, um es auszuwählen. Mit den Pfeilen ändern Sie die Reihenfolge.'**
  String get fieldOrderHint;

  /// T073 field-order review list empty state for a document without confirmed fields.
  ///
  /// In de, this message translates to:
  /// **'Noch keine bestätigten Felder in der Reihenfolge.'**
  String get fieldOrderEmpty;

  /// T073 field-order review row: one-based position index and total field count.
  ///
  /// In de, this message translates to:
  /// **'{index} von {count}'**
  String fieldOrderPosition(int index, int count);

  /// T073 field-order review row action: move the field one position towards the start (FR-026).
  ///
  /// In de, this message translates to:
  /// **'Nach oben'**
  String get fieldOrderMoveUp;

  /// T073 field-order review row action: move the field one position towards the end (FR-026).
  ///
  /// In de, this message translates to:
  /// **'Nach unten'**
  String get fieldOrderMoveDown;

  /// T073 field-order review traversal: select the previous field in the current order (contracts/editor-interactions.md §5).
  ///
  /// In de, this message translates to:
  /// **'Vorheriges Feld'**
  String get fieldOrderPreviousField;

  /// T073 per-field action in the value sheet: commit the draft and open the field-order review (contracts/editor-interactions.md §3, FR-026).
  ///
  /// In de, this message translates to:
  /// **'In Reihenfolge verschieben'**
  String get fieldOrderMoveAction;

  /// T073 field-order review action: reorder every confirmed field into the deterministic page and reading order (FR-026 page order).
  ///
  /// In de, this message translates to:
  /// **'In Seitenreihenfolge sortieren'**
  String get fieldOrderApplyPageOrder;

  /// T073 field-order review traversal: select the next field in the current order (contracts/editor-interactions.md §5).
  ///
  /// In de, this message translates to:
  /// **'Nächstes Feld'**
  String get fieldOrderNextField;

  /// T073 field-order review row: T085 completion state complete (FR-041).
  ///
  /// In de, this message translates to:
  /// **'Vollständig'**
  String get fieldCompletionComplete;

  /// T073 field-order review row: T085 completion state optionalEmpty, a valid optional state that counts as complete.
  ///
  /// In de, this message translates to:
  /// **'Leer (optional)'**
  String get fieldCompletionOptionalEmpty;

  /// T073 field-order review row: T085 completion state blockingError (FR-041).
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get fieldCompletionBlockingError;

  /// T073 field-order review row: T085 completion state warning, kept and not blocking.
  ///
  /// In de, this message translates to:
  /// **'Hinweis'**
  String get fieldCompletionWarning;

  /// T073 field-order review row: T085 completion state incompatible with preserved content that needs a user decision.
  ///
  /// In de, this message translates to:
  /// **'Inhalt passt nicht'**
  String get fieldCompletionIncompatible;

  /// T086D document overview route: US4 scenario 8 / FR-041 per-field completion overview; separate route reachable from the editor without losing edits (contracts/editor-interactions.md §1 and §7).
  ///
  /// In de, this message translates to:
  /// **'Dokumentübersicht'**
  String get documentOverviewTitle;

  /// T086D document overview action: return to the editor and continue filling; the overview never owns a value, so returning loses nothing (US4 scenario 8, FR-039).
  ///
  /// In de, this message translates to:
  /// **'Weiter ausfüllen'**
  String get documentOverviewContinue;

  /// contracts/error-catalog.de.md §3 SAVE-001: Storage full / quota exceeded.
  ///
  /// In de, this message translates to:
  /// **'Der Speicherplatz reicht nicht aus. Der letzte gespeicherte Stand ist erhalten; die neuesten Änderungen sind noch nicht dauerhaft gespeichert.'**
  String get save001;

  /// contracts/error-catalog.de.md §3 SAVE-001: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte geben Sie Speicherplatz frei und versuchen Sie es erneut. Feldexa löscht keine Ihrer Dokumente.'**
  String get save001Recovery;

  /// contracts/error-catalog.de.md §3 SAVE-002: key material for one document/template unavailable/invalidated; the aggregate's own KEK is affected.
  ///
  /// In de, this message translates to:
  /// **'Die gespeicherten Daten können nicht entschlüsselt werden, weil der zugehörige Schlüssel nicht mehr verfügbar ist; das betroffene Dokument oder die betroffene Vorlage kann nicht geöffnet werden. Andere Dokumente und Vorlagen sind davon nicht betroffen.'**
  String get save002;

  /// contracts/error-catalog.de.md §3 SAVE-002: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Eine Wiederherstellung ist nicht möglich. Bitte wenden Sie sich an den Gerätehersteller, wenn der Schlüssel durch einen Gerätefehler verloren gegangen ist.'**
  String get save002Recovery;

  /// contracts/error-catalog.de.md §3 SAVE-003: Write failed or stored data corrupted.
  ///
  /// In de, this message translates to:
  /// **'Speichern ist fehlgeschlagen. Der zuletzt erfolgreich gespeicherte Stand bleibt erhalten.'**
  String get save003;

  /// contracts/error-catalog.de.md §3 SAVE-003: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte versuchen Sie es erneut. Wenn der Fehler bleibt, prüfen Sie den freien Speicherplatz.'**
  String get save003Recovery;

  /// contracts/error-catalog.de.md §3 SAVE-004: Recovery fell back to older revision.
  ///
  /// In de, this message translates to:
  /// **'Feldexa hat einen älteren gespeicherten Stand wiederhergestellt, weil der neueste Stand nicht lesbar war. Änderungen seit diesem Stand können verloren sein.'**
  String get save004;

  /// contracts/error-catalog.de.md §3 SAVE-004: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte prüfen Sie das Dokument und speichern Sie es erneut.'**
  String get save004Recovery;

  /// contracts/error-catalog.de.md §3 SAVE-005: Data written by a newer app version.
  ///
  /// In de, this message translates to:
  /// **'Dieses Dokument wurde mit einer neueren Version von Feldexa gespeichert. Bitte aktualisieren Sie die App, um es zu öffnen. Die Daten bleiben unverändert.'**
  String get save005;

  /// contracts/error-catalog.de.md §3 SAVE-005: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Öffnen Sie das Dokument erst nach dem Update wieder.'**
  String get save005Recovery;

  /// contracts/error-catalog.de.md §3 SAVE-006: Concurrent save conflict.
  ///
  /// In de, this message translates to:
  /// **'Das Speichern konnte nicht abgeschlossen werden. Bitte versuchen Sie es erneut.'**
  String get save006;

  /// contracts/error-catalog.de.md §3 SAVE-007: Invalid data rejected (oversized/invalid payload).
  ///
  /// In de, this message translates to:
  /// **'Die Änderung konnte nicht gespeichert werden, weil die Daten ungültig sind. Der letzte gespeicherte Stand bleibt erhalten.'**
  String get save007;

  /// contracts/error-catalog.de.md §3 SAVE-007: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte prüfen Sie sehr lange Eingaben und versuchen Sie es erneut.'**
  String get save007Recovery;

  /// contracts/error-catalog.de.md §3 SAVE-008: global Keystore provider outage or device-wide key-store reset; all stored aggregates may be affected.
  ///
  /// In de, this message translates to:
  /// **'Die Schlüssel des Geräts sind nicht verfügbar; alle gespeicherten Dokumente und Vorlagen können vorübergehend oder dauerhaft nicht geöffnet werden. Bitte entsperren Sie das Gerät und versuchen Sie es erneut.'**
  String get save008;

  /// contracts/error-catalog.de.md §3 SAVE-008: recovery guidance for global key-store unavailability.
  ///
  /// In de, this message translates to:
  /// **'Wenn das Problem bleibt, starten Sie das Gerät neu; verlorene Schlüssel können nicht wiederhergestellt werden.'**
  String get save008Recovery;

  /// §3 PRIV-001: pre-emptive key/backup disclosure for aggregate key loss and the global device/Keystore reset exception, shown before the first save (FR-051/FR-089).
  ///
  /// In de, this message translates to:
  /// **'Ihre Dokumente und Vorlagen werden nur auf diesem Gerät und mit Schlüsseln gespeichert, die an dieses Gerät gebunden sind. Sicherungskopien der App-Daten sind nicht möglich. Wenn der Schlüssel eines Dokuments oder einer Vorlage verloren geht, können die betroffenen Daten nicht wiederhergestellt werden. Andere Dokumente und Vorlagen bleiben unabhängig davon nutzbar. Ein Zurücksetzen des Geräts oder seiner Schlüssel kann dagegen alle gespeicherten Dokumente und Vorlagen unlesbar machen oder entfernen; eine Wiederherstellung ist dann nicht möglich.'**
  String get priv001;

  /// §3 durability label `clean`: no changes since the verified commit (FR-046).
  ///
  /// In de, this message translates to:
  /// **'Gespeichert'**
  String get durabilityClean;

  /// §3 durability label `saving`: commit in progress, not yet durable (FR-046).
  ///
  /// In de, this message translates to:
  /// **'Wird gespeichert …'**
  String get durabilitySaving;

  /// §3 durability label `saved`: verified durable commit (FR-046).
  ///
  /// In de, this message translates to:
  /// **'Gespeichert um {time}'**
  String durabilitySaved(String time);

  /// §3 durability label `unsaved`: in-memory changes only (FR-046).
  ///
  /// In de, this message translates to:
  /// **'Nicht gespeichert – Änderungen sind gefährdet'**
  String get durabilityUnsaved;

  /// §3 durability label `saveFailed`: failure with preserved prior state (FR-046).
  ///
  /// In de, this message translates to:
  /// **'Speichern fehlgeschlagen – letzter gespeicherter Stand: {time}'**
  String durabilitySaveFailed(String time);

  /// §3 durability label `recoveryFallback`: fallback after corruption (FR-046).
  ///
  /// In de, this message translates to:
  /// **'Älterer Stand wiederhergestellt'**
  String get durabilityRecoveryFallback;

  /// contracts/error-catalog.de.md §4 EXP-001: Content would be clipped/overflow.
  ///
  /// In de, this message translates to:
  /// **'Der Export wurde gestoppt, weil der Inhalt in {count} Feld/Feldern nicht vollständig Platz hat: {fields}. Es wurde keine PDF-Datei erstellt.'**
  String exp001(int count, String fields);

  /// contracts/error-catalog.de.md §4 EXP-001: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte kürzen Sie den Text oder vergrößern Sie die betroffenen Felder und starten Sie den Export erneut.'**
  String get exp001Recovery;

  /// contracts/error-catalog.de.md §4 EXP-002: Export failed/interrupted.
  ///
  /// In de, this message translates to:
  /// **'Der Export ist fehlgeschlagen. Es wurde keine gültige PDF-Datei erstellt. Ihr Dokument ist unverändert.'**
  String get exp002;

  /// contracts/error-catalog.de.md §4 EXP-002: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte prüfen Sie den freien Speicherplatz und versuchen Sie es erneut.'**
  String get exp002Recovery;

  /// contracts/error-catalog.de.md §4 EXP-003: Field geometry outside page.
  ///
  /// In de, this message translates to:
  /// **'Der Export wurde gestoppt, weil mindestens ein Feld außerhalb der Seite liegt: {fields}. Es wurde keine PDF-Datei erstellt.'**
  String exp003(String fields);

  /// contracts/error-catalog.de.md §4 EXP-003: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte verschieben Sie die betroffenen Felder auf die Seite und versuchen Sie es erneut.'**
  String get exp003Recovery;

  /// contracts/error-catalog.de.md §4 EXP-004: Character not renderable.
  ///
  /// In de, this message translates to:
  /// **'Der Export wurde gestoppt, weil ein Zeichen nicht dargestellt werden kann: {fields}. Es wurde keine PDF-Datei erstellt.'**
  String exp004(String fields);

  /// contracts/error-catalog.de.md §4 EXP-004: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte entfernen Sie das betroffene Zeichen oder ersetzen Sie es und versuchen Sie es erneut.'**
  String get exp004Recovery;

  /// contracts/error-catalog.de.md §4 EXP-005: Stored source unreadable.
  ///
  /// In de, this message translates to:
  /// **'Der Export ist nicht möglich, weil die gespeicherte Originaldatei nicht mehr gelesen werden kann. Ihr bearbeitetes Dokument bleibt erhalten.'**
  String get exp005;

  /// contracts/error-catalog.de.md §4 EXP-005: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte importieren Sie das Original erneut und übertragen Sie Ihre Angaben.'**
  String get exp005Recovery;

  /// contracts/error-catalog.de.md §4 EXP-006: A page cannot be copied.
  ///
  /// In de, this message translates to:
  /// **'Der Export wurde gestoppt, weil Seite {page} nicht übernommen werden kann. Es wurde keine PDF-Datei erstellt. Seiten werden nicht stillschweigend weggelassen.'**
  String exp006(int page);

  /// contracts/error-catalog.de.md §4 EXP-006: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte prüfen Sie das Original oder importieren Sie es erneut. Andere Seiten und Ihre Eingaben bleiben erhalten.'**
  String get exp006Recovery;

  /// contracts/error-catalog.de.md §4 SAVE-001: No space during export.
  ///
  /// In de, this message translates to:
  /// **'Der Speicherplatz reicht für den Export nicht aus. Es wurde keine gültige PDF-Datei erstellt.'**
  String get save001Export;

  /// contracts/error-catalog.de.md §4 SAVE-001: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte geben Sie Speicherplatz frei und versuchen Sie es erneut.'**
  String get save001ExportRecovery;

  /// §4 pre-export information: empty fields never block export (FR-062).
  ///
  /// In de, this message translates to:
  /// **'{empty} Felder sind noch leer. Leere Felder werden nicht ausgefüllt, der Export bleibt möglich.'**
  String preExportEmptyFields(int empty);

  /// §4 pre-export information: unreviewed suggestions are excluded under the ratified OD-1/Q1=A policy.
  ///
  /// In de, this message translates to:
  /// **'{count} Vorschläge sind noch nicht geprüft. Sie werden nicht in die PDF-Datei übernommen.'**
  String preExportUnreviewedSuggestions(int count);

  /// §4 export success message; never claims guaranteed correctness.
  ///
  /// In de, this message translates to:
  /// **'Die PDF-Datei ist fertig und wurde geprüft. Sie können sie ansehen, speichern, teilen oder drucken.'**
  String get exportSuccess;

  /// §4 preview footer of the in-app export preview.
  ///
  /// In de, this message translates to:
  /// **'Vorschau der erzeugten PDF-Datei'**
  String get previewFooter;

  /// Issue #334 export preview: page count of the verified artifact. contracts/editor-interactions.md §10 point 4 requires the preview to show the produced artifact.
  ///
  /// In de, this message translates to:
  /// **'Seiten: {count}'**
  String exportPreviewPageCount(int count);

  /// Issue #334 export preview: byte size of the verified artifact, formatted with a German decimal comma.
  ///
  /// In de, this message translates to:
  /// **'Dateigröße: {size}'**
  String exportPreviewFileSize(String size);

  /// contracts/editor-interactions.md §10 point 4: preview action `Speichern`.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get exportPreviewSaveAction;

  /// contracts/editor-interactions.md §10 point 4: preview action `Teilen`.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get exportPreviewShareAction;

  /// contracts/editor-interactions.md §10 point 4: preview action `Drucken`.
  ///
  /// In de, this message translates to:
  /// **'Drucken'**
  String get exportPreviewPrintAction;

  /// contracts/editor-interactions.md §10 point 4: closing action of the export preview and of the pre-export sheet.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get exportCloseAction;

  /// contracts/editor-interactions.md §10 point 2: the action that jumps from a blocking export warning to the first blocking field; the catalog names the label verbatim.
  ///
  /// In de, this message translates to:
  /// **'Zu den Feldern'**
  String get exportPreflightGoToFields;

  /// Issue #334 §10 point 3: heading of the export progress surface. It names only the product (a PDF, §10 points 1 and 4) and never a file name, path, title, or value.
  ///
  /// In de, this message translates to:
  /// **'PDF wird erstellt'**
  String get exportProgressTitle;

  /// Issue #334 §10 point 3, phase `importing` of contracts/platform-channel.md §6: the stored source PDF is read and checked against the plan hash. The catalog has no row for a phase label; the wording names the phase meaning of §6 only.
  ///
  /// In de, this message translates to:
  /// **'Original wird gelesen'**
  String get exportProgressImporting;

  /// Issue #334 §10 point 3, phase `drawing` of contracts/platform-channel.md §6: every page is copied and receives its overlay operations. Content-free: no page count, field, or value.
  ///
  /// In de, this message translates to:
  /// **'Seiten werden gezeichnet'**
  String get exportProgressDrawing;

  /// Issue #334 §10 point 3, phase `verifying` of contracts/platform-channel.md §6 and export-plan.md §5 step 5: the written artifact is verified before anything is published. Uses the catalog's own verb „geprüft“ (§4 export success).
  ///
  /// In de, this message translates to:
  /// **'PDF-Datei wird geprüft'**
  String get exportProgressVerifying;

  /// Issue #334 §10 point 3, phase `finalizing` of contracts/platform-channel.md §6: the verified artifact is renamed into place and published.
  ///
  /// In de, this message translates to:
  /// **'PDF-Datei wird abgeschlossen'**
  String get exportProgressFinalizing;

  /// Issue #334 §10 point 3: the cancel action of the export progress surface. The catalog has no row for it; the label is the standard German cancel label, and cancellation publishes the developer-only PLT-004 of contracts/platform-channel.md §9, which has no user-facing text.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get exportProgressCancelAction;

  /// contracts/error-catalog.de.md §5 TPL-001: Template creation impossible (no confirmed fields or source unreadable).
  ///
  /// In de, this message translates to:
  /// **'Eine Vorlage kann nicht erstellt werden, weil noch keine Felder bestätigt sind oder die Originalseiten nicht lesbar sind.'**
  String get tpl001;

  /// contracts/error-catalog.de.md §5 TPL-001: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte prüfen und bestätigen Sie zuerst die Felder.'**
  String get tpl001Recovery;

  /// contracts/error-catalog.de.md §5 TPL-002: Template save failed.
  ///
  /// In de, this message translates to:
  /// **'Die Vorlage konnte nicht gespeichert werden. Bereits vorhandene Vorlagenversionen bleiben unverändert.'**
  String get tpl002;

  /// contracts/error-catalog.de.md §5 TPL-002: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte prüfen Sie den freien Speicherplatz und versuchen Sie es erneut.'**
  String get tpl002Recovery;

  /// contracts/error-catalog.de.md §5 TPL-003: Template opened for editing contains values (internal invariant).
  ///
  /// In de, this message translates to:
  /// **'Die Vorlage konnte nicht geöffnet werden, weil sie unerwartete Eingaben enthält. Es wurden keine Daten geändert.'**
  String get tpl003;

  /// contracts/error-catalog.de.md §5 TPL-003: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte versuchen Sie es erneut oder erstellen Sie die Vorlage neu.'**
  String get tpl003Recovery;

  /// §5/§8 template action label.
  ///
  /// In de, this message translates to:
  /// **'Als Vorlage speichern'**
  String get templateSaveAction;

  /// §5 template label.
  ///
  /// In de, this message translates to:
  /// **'Vorlage'**
  String get templateLabel;

  /// §5 template version label.
  ///
  /// In de, this message translates to:
  /// **'Vorlagenversion {n} vom {date}'**
  String templateVersionLabel(int n, String date);

  /// §5 confirmation after saving a new template version.
  ///
  /// In de, this message translates to:
  /// **'Neue Version gespeichert'**
  String get templateNewVersionSaved;

  /// §5 template editor hint: templates never store values or signatures.
  ///
  /// In de, this message translates to:
  /// **'In einer Vorlage werden nur Felder und Seiten gespeichert – keine Eingaben und keine Unterschriften.'**
  String get templateEditorHint;

  /// contracts/error-catalog.de.md §6 DATE-001: Malformed date.
  ///
  /// In de, this message translates to:
  /// **'Bitte geben Sie ein gültiges Datum im Format Tag.Monat.Jahr ein, zum Beispiel 31.12.2025.'**
  String get date001;

  /// contracts/error-catalog.de.md §6 DATE-002: Impossible calendar date (e.g., 31.02.2025).
  ///
  /// In de, this message translates to:
  /// **'Dieses Datum existiert nicht. Bitte geben Sie ein gültiges Datum im Format Tag.Monat.Jahr ein.'**
  String get date002;

  /// contracts/error-catalog.de.md §6 DATE-002: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Prüfen Sie Tag und Monat.'**
  String get date002Recovery;

  /// contracts/error-catalog.de.md §6 NUM-001: Invalid number.
  ///
  /// In de, this message translates to:
  /// **'Bitte geben Sie eine gültige Zahl ein, zum Beispiel 1234,56.'**
  String get num001;

  /// contracts/error-catalog.de.md §6 FLD-001: Text longer than field.
  ///
  /// In de, this message translates to:
  /// **'Der Text ist länger als das Feld. Er wurde nicht gekürzt. Der Export wird gestoppt, bis der Text gekürzt oder das Feld vergrößert ist.'**
  String get fld001;

  /// contracts/error-catalog.de.md §6 FLD-001: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte kürzen Sie den Text oder vergrößern Sie das Feld.'**
  String get fld001Recovery;

  /// contracts/error-catalog.de.md §6 FLD-002: Incompatible content after type change.
  ///
  /// In de, this message translates to:
  /// **'Der bisherige Inhalt passt nicht zum neuen Feldtyp. Er wurde nicht gelöscht und ist weiterhin sichtbar.'**
  String get fld002;

  /// contracts/error-catalog.de.md §6 FLD-002: recovery guidance.
  ///
  /// In de, this message translates to:
  /// **'Bitte prüfen Sie den Inhalt und übernehmen, ändern oder verwerfen Sie ihn bewusst.'**
  String get fld002Recovery;

  /// contracts/error-catalog.de.md §6 FLD-003: Conflict between suggestions.
  ///
  /// In de, this message translates to:
  /// **'Zwei Vorschläge überlappen sich. Bitte entscheiden Sie für jeden Vorschlag einzeln, ob er übernommen wird.'**
  String get fld003;

  /// §7 DEL-002 document deletion dialog (FR-076).
  ///
  /// In de, this message translates to:
  /// **'Möchten Sie „{title}“ wirklich löschen? Gelöscht werden die gespeicherten Seiten, Felder, Eingaben und Unterschriften dieses Dokuments. Andere Dokumente und Vorlagen bleiben erhalten.'**
  String deleteDocumentDialog(String title);

  /// §7 DEL-003 template deletion dialog.
  ///
  /// In de, this message translates to:
  /// **'Möchten Sie die Vorlage „{title}“ mit allen Versionen wirklich löschen? Dokumente, die aus dieser Vorlage erstellt wurden, bleiben unverändert und weiterhin nutzbar.'**
  String deleteTemplateDialog(String title);

  /// §7 confirmation after deletion.
  ///
  /// In de, this message translates to:
  /// **'„{title}“ wurde gelöscht. Andere Dokumente und Vorlagen wurden nicht verändert.'**
  String deletionConfirmation(String title);

  /// §8 documents group heading.
  ///
  /// In de, this message translates to:
  /// **'Dokumente'**
  String get documentsGroup;

  /// §8 templates group heading.
  ///
  /// In de, this message translates to:
  /// **'Vorlagen'**
  String get templatesGroup;

  /// §8 empty documents state.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Dokumente. Importieren Sie eine gescannte PDF-Datei, um zu beginnen.'**
  String get emptyDocuments;

  /// §8 empty templates state.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Vorlagen. Speichern Sie ein geprüftes Dokument als Vorlage.'**
  String get emptyTemplates;

  /// §8 import action.
  ///
  /// In de, this message translates to:
  /// **'PDF importieren'**
  String get importAction;

  /// §8 document status `draft`.
  ///
  /// In de, this message translates to:
  /// **'In Bearbeitung'**
  String get statusDraft;

  /// §8 document status `export-ready`.
  ///
  /// In de, this message translates to:
  /// **'Exportbereit'**
  String get statusExportReady;

  /// §8 document status `unreadable`.
  ///
  /// In de, this message translates to:
  /// **'Nicht lesbar'**
  String get statusUnreadable;

  /// contracts/error-catalog.de.md §8 page analysis state `pending`: short visible form in one page-strip control.
  ///
  /// In de, this message translates to:
  /// **'Wartet'**
  String get pageAnalysisPending;

  /// contracts/error-catalog.de.md §8 page analysis state `pending`: full form used as the semantic hint and in the compact page indicator.
  ///
  /// In de, this message translates to:
  /// **'Analyse ausstehend'**
  String get pageAnalysisPendingHint;

  /// contracts/error-catalog.de.md §8 page analysis state `analyzing`: short visible form in one page-strip control.
  ///
  /// In de, this message translates to:
  /// **'Läuft'**
  String get pageAnalysisAnalyzing;

  /// contracts/error-catalog.de.md §8 page analysis state `analyzing`: full form used as the semantic hint and in the compact page indicator.
  ///
  /// In de, this message translates to:
  /// **'Analyse läuft'**
  String get pageAnalysisAnalyzingHint;

  /// contracts/error-catalog.de.md §8 page analysis state `complete`: short visible form in one page-strip control.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get pageAnalysisComplete;

  /// contracts/error-catalog.de.md §8 page analysis state `complete`: full form used as the semantic hint and in the compact page indicator.
  ///
  /// In de, this message translates to:
  /// **'Analyse abgeschlossen'**
  String get pageAnalysisCompleteHint;

  /// contracts/error-catalog.de.md §8 page analysis state `failed`: short visible form in one page-strip control.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get pageAnalysisFailed;

  /// contracts/error-catalog.de.md §8 page analysis state `failed`: full form used as the semantic hint and in the compact page indicator.
  ///
  /// In de, this message translates to:
  /// **'Analyse fehlgeschlagen'**
  String get pageAnalysisFailedHint;

  /// §8 field count summary.
  ///
  /// In de, this message translates to:
  /// **'{count} Felder, {filled} ausgefüllt'**
  String fieldCount(int count, int filled);

  /// §8 last-edited label.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt bearbeitet: {date}'**
  String lastEdited(String date);

  /// §8 review action.
  ///
  /// In de, this message translates to:
  /// **'Felder prüfen'**
  String get reviewAction;

  /// §8 fill action.
  ///
  /// In de, this message translates to:
  /// **'Ausfüllen'**
  String get fillAction;

  /// §8 export action.
  ///
  /// In de, this message translates to:
  /// **'PDF exportieren'**
  String get exportAction;

  /// §8 explicit save action.
  ///
  /// In de, this message translates to:
  /// **'Jetzt speichern'**
  String get saveNow;

  /// §8 unsaved badge.
  ///
  /// In de, this message translates to:
  /// **'Nicht gespeichert'**
  String get unsavedBadge;

  /// §8 unsaved-risk banner.
  ///
  /// In de, this message translates to:
  /// **'Ihre letzten Änderungen sind noch nicht dauerhaft gespeichert. Verlassen Sie die App nicht, bis „Gespeichert“ erscheint.'**
  String get unsavedRiskBanner;

  /// §8 accessibility field-overlay semantics; `filled`, `status`, `conflict`, and `uncertainty` receive the German fragment values below.
  ///
  /// In de, this message translates to:
  /// **'Feld {label}, Typ {type}, Seite {page}, {filled}, {status}{conflict}{uncertainty}'**
  String a11yFieldOverlay(
    String label,
    String type,
    int page,
    String filled,
    String status,
    String conflict,
    String uncertainty,
  );

  /// §8 accessibility field-overlay value: the field has a confirmed value.
  ///
  /// In de, this message translates to:
  /// **'ausgefüllt'**
  String get a11yFieldValueFilled;

  /// §8 accessibility field-overlay value: the field is empty.
  ///
  /// In de, this message translates to:
  /// **'leer'**
  String get a11yFieldValueEmpty;

  /// §8 accessibility field-overlay status: confirmed.
  ///
  /// In de, this message translates to:
  /// **'bestätigt'**
  String get a11yFieldStatusConfirmed;

  /// §8 accessibility field-overlay status: unconfirmed suggestion.
  ///
  /// In de, this message translates to:
  /// **'Vorschlag'**
  String get a11yFieldStatusSuggestion;

  /// §8 accessibility field-overlay status: created by the user.
  ///
  /// In de, this message translates to:
  /// **'selbst erstellt'**
  String get a11yFieldStatusSelfCreated;

  /// §8 optional accessibility suffix for a conflicting field.
  ///
  /// In de, this message translates to:
  /// **', Konflikt'**
  String get a11yFieldConflict;

  /// §8 optional accessibility suffix for an uncertain suggestion.
  ///
  /// In de, this message translates to:
  /// **', unsicher'**
  String get a11yFieldUncertain;

  /// §8 accessibility suggestion semantics (FR-094).
  ///
  /// In de, this message translates to:
  /// **'Vorschlag für {type} bei {label}, Zuverlässigkeit {percent} Prozent, nicht bestätigt'**
  String a11ySuggestion(String type, String label, int percent);

  /// §8 accessibility checkbox semantics; `state` is one of the two fragments below.
  ///
  /// In de, this message translates to:
  /// **'Kontrollkästchen {label}, {state}'**
  String a11yCheckbox(String label, String state);

  /// §8 accessibility checkbox state: checked.
  ///
  /// In de, this message translates to:
  /// **'aktiviert'**
  String get a11yCheckboxChecked;

  /// §8 accessibility checkbox state: unchecked.
  ///
  /// In de, this message translates to:
  /// **'nicht aktiviert'**
  String get a11yCheckboxUnchecked;

  /// §8 accessibility signature-field semantics; `state` is one of the two fragments below.
  ///
  /// In de, this message translates to:
  /// **'Unterschriftenfeld {label}, {state}'**
  String a11ySignature(String label, String state);

  /// §8 accessibility signature state: signed.
  ///
  /// In de, this message translates to:
  /// **'unterschrieben'**
  String get a11ySignatureSigned;

  /// §8 accessibility signature state: unsigned.
  ///
  /// In de, this message translates to:
  /// **'nicht unterschrieben'**
  String get a11ySignatureUnsigned;

  /// §8 accessibility page-navigation semantics.
  ///
  /// In de, this message translates to:
  /// **'Seite {page} von {count}'**
  String a11yPageNavigation(int page, int count);

  /// §8 accessibility zoom semantics.
  ///
  /// In de, this message translates to:
  /// **'Vergrößerung {percent} Prozent'**
  String a11yZoom(int percent);

  /// §8 exact SIMULATED banner, including the untranslated mandated token (FR-087).
  ///
  /// In de, this message translates to:
  /// **'SIMULATED – Entwicklungsansicht mit simulierten Plattformfunktionen. Keine Android-Prüfung.'**
  String get simulatedBanner;

  /// §9 required exact untranslated evidence token; never translated or hidden (FR-087).
  ///
  /// In de, this message translates to:
  /// **'SIMULATED'**
  String get simulatedToken;

  /// §9 exact log prefix.
  ///
  /// In de, this message translates to:
  /// **'[SIMULATED]'**
  String get simulatedLogPrefix;

  /// §9 German context line for the global SIMULATED banner.
  ///
  /// In de, this message translates to:
  /// **'Entwicklungsansicht: Plattformfunktionen sind simuliert. Ergebnisse gelten nicht als Android-Nachweis.'**
  String get simulatedBannerContext;

  /// §9 German context line for the simulated export footer.
  ///
  /// In de, this message translates to:
  /// **'Simuliertes PDF – kein Produktionsartefakt.'**
  String get simulatedExportFooterContext;

  /// §9 German context line for the simulated storage notice.
  ///
  /// In de, this message translates to:
  /// **'Simulierter Speicher – keine echte Verschlüsselung.'**
  String get simulatedStorageContext;

  /// §11 rule 5: non-destructive acknowledgment action in an error dialog.
  ///
  /// In de, this message translates to:
  /// **'Verstanden'**
  String get actionUnderstood;

  /// §11 rule 5: retry action in an error dialog.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get actionRetry;

  /// §11 rule 5: storage-recovery action in an error dialog.
  ///
  /// In de, this message translates to:
  /// **'Speicherplatz prüfen'**
  String get actionCheckStorage;

  /// T115 FR-054: explicit editor app-bar action that saves the current reviewed document as a template; never automatic (FR-061).
  ///
  /// In de, this message translates to:
  /// **'Als Vorlage speichern'**
  String get saveAsTemplateAction;

  /// T115: title of the Als-Vorlage-speichern sheet.
  ///
  /// In de, this message translates to:
  /// **'Vorlage erstellen'**
  String get createTemplateSheetTitle;

  /// T115: label of the template title input.
  ///
  /// In de, this message translates to:
  /// **'Titel der Vorlage'**
  String get createTemplateTitleLabel;

  /// T115 FR-057: notice that entered values and signatures are excluded from the saved template.
  ///
  /// In de, this message translates to:
  /// **'Werte und Unterschriften werden nicht in die Vorlage übernommen.'**
  String get createTemplateExclusionNotice;

  /// T115 FR-055: notice shown while the field structure is not fully reviewed.
  ///
  /// In de, this message translates to:
  /// **'Die Feldstruktur muss zuerst vollständig geprüft sein.'**
  String get createTemplateStructurePending;

  /// T115: confirm action of the Als-Vorlage-speichern sheet.
  ///
  /// In de, this message translates to:
  /// **'Vorlage speichern'**
  String get createTemplateConfirm;

  /// T115: content-free success notice after a verified template creation.
  ///
  /// In de, this message translates to:
  /// **'Vorlage gespeichert.'**
  String get createTemplateSuccess;

  /// T115 FR-106 pattern: content-free failure notice; no optimistic success.
  ///
  /// In de, this message translates to:
  /// **'Das Speichern der Vorlage ist fehlgeschlagen. Die Vorlage wurde nicht gespeichert.'**
  String get createTemplateFailed;

  /// T117: title of the use-template sheet.
  ///
  /// In de, this message translates to:
  /// **'Dokument aus Vorlage erstellen'**
  String get useTemplateSheetTitle;

  /// T117 FR-059/FR-060: notice that using a template creates an independent document and never mutates the template.
  ///
  /// In de, this message translates to:
  /// **'Es wird ein neues, unabhängiges Dokument mit leeren Werten erstellt. Die Vorlage bleibt unverändert.'**
  String get useTemplateNotice;

  /// T117: confirm action of the use-template sheet.
  ///
  /// In de, this message translates to:
  /// **'Dokument erstellen'**
  String get useTemplateConfirm;

  /// T117 FR-106 pattern: content-free failure notice; no optimistic success.
  ///
  /// In de, this message translates to:
  /// **'Das Erstellen des Dokuments ist fehlgeschlagen. Es wurde kein Dokument erstellt.'**
  String get useTemplateFailed;

  /// T116 FR-101/FR-102: title of the layout-only template editor.
  ///
  /// In de, this message translates to:
  /// **'Vorlage bearbeiten (nur Layout)'**
  String get templateEditorTitle;

  /// T116 FR-102: notice that template editing is layout-only.
  ///
  /// In de, this message translates to:
  /// **'Diese Vorlage kann nur im Layout bearbeitet werden. Werte und Unterschriften können in einer Vorlage nicht erfasst werden.'**
  String get templateEditorLayoutOnlyNotice;

  /// T116/T117 FR-103: action that saves the edited layout as a new immutable template version.
  ///
  /// In de, this message translates to:
  /// **'Als neue Version speichern'**
  String get templateEditorSaveVersion;

  /// T117 FR-103: label of a template version with its display number.
  ///
  /// In de, this message translates to:
  /// **'Version {number}'**
  String templateEditorVersionLabel(int number);

  /// T116 FR-101: semantics hint for moving a layout field.
  ///
  /// In de, this message translates to:
  /// **'Feld verschieben'**
  String get templateEditorMoveFieldHint;

  /// T124 FR-085 document-summary title: names the surface without any completeness claim (error catalog §2).
  ///
  /// In de, this message translates to:
  /// **'Vorschläge und Felder'**
  String get recognitionSummaryTitle;

  /// T124 FR-085 summary row: fields the user created manually.
  ///
  /// In de, this message translates to:
  /// **'Manuell erfasst: {count}'**
  String recognitionSummaryManual(int count);

  /// T124 FR-085 summary row: suggestions confirmed by the user (recognition-output §7, provenance machine).
  ///
  /// In de, this message translates to:
  /// **'Übernommene Vorschläge: {count}'**
  String recognitionSummaryAdopted(int count);

  /// T124 FR-085 summary row: fields inherited from a pinned template version (provenance template).
  ///
  /// In de, this message translates to:
  /// **'Aus Vorlage übernommen: {count}'**
  String recognitionSummaryTemplate(int count);

  /// T124 FR-085 summary row: suggestions still awaiting a decision; wording uses „Vorschläge“, never a completeness claim (error catalog §2).
  ///
  /// In de, this message translates to:
  /// **'Offene Vorschläge: {count}'**
  String recognitionSummaryOpen(int count);

  /// T124 FR-083 summary sub-count: open suggestions below the 0.50 uncertainty threshold.
  ///
  /// In de, this message translates to:
  /// **'davon unsicher: {count}'**
  String recognitionSummaryUncertain(int count);

  /// T124 US8 scenario 5: mandatory no-completeness note on every summary surface (FR-085; error catalog §2).
  ///
  /// In de, this message translates to:
  /// **'Die Erkennung ist unvollständig, bis Sie alle Vorschläge geprüft haben.'**
  String get recognitionSummaryNote;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
