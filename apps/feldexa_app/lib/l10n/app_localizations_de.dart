// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Feldexa';

  @override
  String get startTitle => 'Meine Dokumente';

  @override
  String get startupRecoveryIncomplete =>
      'Die Wiederherstellung beim Start wurde nicht vollständig abgeschlossen. Bitte starten Sie Feldexa erneut.';

  @override
  String get startupRecoveryIncompleteRecovery =>
      'Ihre gespeicherten Dokumente und Vorlagen werden dabei nicht gelöscht. Prüfen Sie nach dem Neustart, ob alle Einträge lesbar sind.';

  @override
  String get imp001 =>
      'Diese PDF-Datei ist passwortgeschützt. Feldexa kann geschützte Dateien nicht öffnen, und Ihr Passwort wird weder abgefragt noch gespeichert.';

  @override
  String get imp001Recovery =>
      'Bitte entfernen Sie den Schutz in einem PDF-Programm, das Sie dafür verwenden dürfen, und importieren Sie die Datei erneut.';

  @override
  String get imp002 =>
      'Die Datei konnte nicht gelesen werden. Sie ist möglicherweise unvollständig oder beschädigt.';

  @override
  String get imp002Recovery =>
      'Bitte öffnen Sie die Datei in einem PDF-Programm, speichern Sie sie erneut und versuchen Sie es noch einmal.';

  @override
  String get imp003 =>
      'Die ausgewählte Datei ist nicht mehr verfügbar. Möglicherweise wurde sie verschoben, umbenannt oder gelöscht.';

  @override
  String get imp003Recovery => 'Bitte wählen Sie die Datei erneut aus.';

  @override
  String get imp004 =>
      'Diese Datei ist kein unterstütztes PDF. Feldexa kann nur PDF-Dokumente importieren.';

  @override
  String get imp004Recovery => 'Bitte wählen Sie eine PDF-Datei aus.';

  @override
  String get imp005 =>
      'Die Datei konnte nicht gelesen werden. Die Ursache lässt sich nicht sicher feststellen.';

  @override
  String get imp005Recovery =>
      'Bitte versuchen Sie es erneut. Wenn das Problem bleibt, öffnen und speichern Sie die Datei in einem PDF-Programm.';

  @override
  String imp006(String pages) {
    return 'Einige Seiten konnten nicht gelesen werden: $pages. Die übrigen Seiten sind nutzbar. Ein Export des vollständigen Dokuments ist dadurch beeinträchtigt.';
  }

  @override
  String get imp006Recovery =>
      'Sie können die betroffenen Seiten prüfen und das Dokument trotzdem weiterbearbeiten.';

  @override
  String get imp007 =>
      'Die Datei ist zu groß. Feldexa kann PDF-Dateien bis 80 MiB (83.886.080 Bytes) importieren.';

  @override
  String get imp007Recovery =>
      'Bitte verkleinern Sie die Datei, zum Beispiel durch eine niedrigere Scan-Auflösung, und importieren Sie sie erneut.';

  @override
  String page001(int page) {
    return 'Seite $page kann nicht angezeigt werden. Die übrigen Seiten bleiben verfügbar.';
  }

  @override
  String get page001Recovery =>
      'Sie können auf dieser Seite trotzdem Felder setzen; der Export bleibt eingeschränkt.';

  @override
  String get rec001 =>
      'Die Texterkennung ist auf diesem Gerät nicht verfügbar. Feldexa erkennt Felder nur anhand des Seitenaufbaus.';

  @override
  String get rec001Recovery => 'Sie können Felder jederzeit selbst ergänzen.';

  @override
  String rec002(int page) {
    return 'Die Felderkennung auf Seite $page ist fehlgeschlagen. Bereits erkannte Seiten bleiben unverändert.';
  }

  @override
  String get rec002Recovery =>
      'Bitte ergänzen Sie fehlende Felder auf dieser Seite selbst oder versuchen Sie es erneut.';

  @override
  String rec003(int page) {
    return 'Seite $page konnte nicht ausgewertet werden. Der Seitenaufbau ist möglicherweise beschädigt.';
  }

  @override
  String get rec003Recovery =>
      'Sie können die Seite weiter anzeigen und Felder manuell hinzufügen.';

  @override
  String get suggestionsLabel => 'Vorschläge';

  @override
  String get suggestionEmpty =>
      'Für dieses Dokument wurden keine Felder vorgeschlagen.';

  @override
  String get suggestionAllReviewed => 'Alle Vorschläge wurden geprüft.';

  @override
  String suggestionOpenCount(int count) {
    return '$count offen';
  }

  @override
  String suggestionFieldCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Felder bestätigt',
      one: '1 Feld bestätigt',
      zero: 'Keine Felder bestätigt',
    );
    return '$_temp0';
  }

  @override
  String suggestionReviewProgress(int confirmed, int rejected) {
    return '$confirmed bestätigt, $rejected abgelehnt';
  }

  @override
  String get suggestionRowFallback => 'Feld';

  @override
  String suggestionFieldLabel(int n) {
    return 'Feld $n';
  }

  @override
  String suggestionPage(int page) {
    return 'Seite $page';
  }

  @override
  String suggestionPosition(String x, String y) {
    return 'x $x pt · y $y pt';
  }

  @override
  String suggestionConfidence(int percent) {
    return 'Zuverlässigkeit $percent %';
  }

  @override
  String get suggestionUncertain => 'unsicher';

  @override
  String get suggestionConflict => 'Konflikt';

  @override
  String get suggestionTypeText => 'Text';

  @override
  String get suggestionTypeNumber => 'Zahl';

  @override
  String get suggestionTypeDate => 'Datum';

  @override
  String get suggestionTypeCheckbox => 'Kontrollkästchen';

  @override
  String get suggestionTypeMultiline => 'Mehrzeiliger Text';

  @override
  String get suggestionTypeSignature => 'Unterschrift';

  @override
  String get suggestionConfirmAction => 'Übernehmen';

  @override
  String get suggestionRejectAction => 'Ablehnen';

  @override
  String get suggestionUndoAction => 'Rückgängig';

  @override
  String get reviewConflictSheetTitle => 'Konflikt lösen';

  @override
  String get reviewConflictSheetBody =>
      'Beide Vorschläge bleiben erhalten, bis Sie für jeden einzeln entschieden haben. Durch Wischen wird kein Konflikt gelöst.';

  @override
  String get reviewConflictCloseAction => 'Schließen';

  @override
  String get reviewConflictStateUnresolved => 'Offen';

  @override
  String get reviewConflictStateConfirmed => 'Bestätigt';

  @override
  String get reviewConflictStateRejected => 'Abgelehnt';

  @override
  String get reviewConflictSingleCandidateNote =>
      'Zu diesem Konflikt ist kein zweiter Vorschlag vorhanden. Der angezeigte Vorschlag bleibt einzeln entscheidbar.';

  @override
  String get reviewConflictBadgeHint =>
      'Konflikt zwischen Vorschlägen. Tippen, um beide Vorschläge einzeln zu entscheiden.';

  @override
  String get fieldOrderTitle => 'Feldreihenfolge';

  @override
  String get fieldOrderHint =>
      'Tippen Sie ein Feld an, um es auszuwählen. Mit den Pfeilen ändern Sie die Reihenfolge.';

  @override
  String get fieldOrderEmpty =>
      'Noch keine bestätigten Felder in der Reihenfolge.';

  @override
  String fieldOrderPosition(int index, int count) {
    return '$index von $count';
  }

  @override
  String get fieldOrderMoveUp => 'Nach oben';

  @override
  String get fieldOrderMoveDown => 'Nach unten';

  @override
  String get fieldOrderPreviousField => 'Vorheriges Feld';

  @override
  String get fieldOrderNextField => 'Nächstes Feld';

  @override
  String get fieldCompletionComplete => 'Vollständig';

  @override
  String get fieldCompletionOptionalEmpty => 'Leer (optional)';

  @override
  String get fieldCompletionBlockingError => 'Fehler';

  @override
  String get fieldCompletionWarning => 'Hinweis';

  @override
  String get fieldCompletionIncompatible => 'Inhalt passt nicht';

  @override
  String get save001 =>
      'Der Speicherplatz reicht nicht aus. Der letzte gespeicherte Stand ist erhalten; die neuesten Änderungen sind noch nicht dauerhaft gespeichert.';

  @override
  String get save001Recovery =>
      'Bitte geben Sie Speicherplatz frei und versuchen Sie es erneut. Feldexa löscht keine Ihrer Dokumente.';

  @override
  String get save002 =>
      'Die gespeicherten Daten können nicht entschlüsselt werden, weil der zugehörige Schlüssel nicht mehr verfügbar ist; das betroffene Dokument oder die betroffene Vorlage kann nicht geöffnet werden. Andere Dokumente und Vorlagen sind davon nicht betroffen.';

  @override
  String get save002Recovery =>
      'Eine Wiederherstellung ist nicht möglich. Bitte wenden Sie sich an den Gerätehersteller, wenn der Schlüssel durch einen Gerätefehler verloren gegangen ist.';

  @override
  String get save003 =>
      'Speichern ist fehlgeschlagen. Der zuletzt erfolgreich gespeicherte Stand bleibt erhalten.';

  @override
  String get save003Recovery =>
      'Bitte versuchen Sie es erneut. Wenn der Fehler bleibt, prüfen Sie den freien Speicherplatz.';

  @override
  String get save004 =>
      'Feldexa hat einen älteren gespeicherten Stand wiederhergestellt, weil der neueste Stand nicht lesbar war. Änderungen seit diesem Stand können verloren sein.';

  @override
  String get save004Recovery =>
      'Bitte prüfen Sie das Dokument und speichern Sie es erneut.';

  @override
  String get save005 =>
      'Dieses Dokument wurde mit einer neueren Version von Feldexa gespeichert. Bitte aktualisieren Sie die App, um es zu öffnen. Die Daten bleiben unverändert.';

  @override
  String get save005Recovery =>
      'Öffnen Sie das Dokument erst nach dem Update wieder.';

  @override
  String get save006 =>
      'Das Speichern konnte nicht abgeschlossen werden. Bitte versuchen Sie es erneut.';

  @override
  String get save007 =>
      'Die Änderung konnte nicht gespeichert werden, weil die Daten ungültig sind. Der letzte gespeicherte Stand bleibt erhalten.';

  @override
  String get save007Recovery =>
      'Bitte prüfen Sie sehr lange Eingaben und versuchen Sie es erneut.';

  @override
  String get save008 =>
      'Die Schlüssel des Geräts sind nicht verfügbar; alle gespeicherten Dokumente und Vorlagen können vorübergehend oder dauerhaft nicht geöffnet werden. Bitte entsperren Sie das Gerät und versuchen Sie es erneut.';

  @override
  String get save008Recovery =>
      'Wenn das Problem bleibt, starten Sie das Gerät neu; verlorene Schlüssel können nicht wiederhergestellt werden.';

  @override
  String get priv001 =>
      'Ihre Dokumente und Vorlagen werden nur auf diesem Gerät und mit Schlüsseln gespeichert, die an dieses Gerät gebunden sind. Sicherungskopien der App-Daten sind nicht möglich. Wenn der Schlüssel eines Dokuments oder einer Vorlage verloren geht, können die betroffenen Daten nicht wiederhergestellt werden. Andere Dokumente und Vorlagen bleiben unabhängig davon nutzbar. Ein Zurücksetzen des Geräts oder seiner Schlüssel kann dagegen alle gespeicherten Dokumente und Vorlagen unlesbar machen oder entfernen; eine Wiederherstellung ist dann nicht möglich.';

  @override
  String get durabilityClean => 'Gespeichert';

  @override
  String get durabilitySaving => 'Wird gespeichert …';

  @override
  String durabilitySaved(String time) {
    return 'Gespeichert um $time';
  }

  @override
  String get durabilityUnsaved =>
      'Nicht gespeichert – Änderungen sind gefährdet';

  @override
  String durabilitySaveFailed(String time) {
    return 'Speichern fehlgeschlagen – letzter gespeicherter Stand: $time';
  }

  @override
  String get durabilityRecoveryFallback => 'Älterer Stand wiederhergestellt';

  @override
  String exp001(int count, String fields) {
    return 'Der Export wurde gestoppt, weil der Inhalt in $count Feld/Feldern nicht vollständig Platz hat: $fields. Es wurde keine PDF-Datei erstellt.';
  }

  @override
  String get exp001Recovery =>
      'Bitte kürzen Sie den Text oder vergrößern Sie die betroffenen Felder und starten Sie den Export erneut.';

  @override
  String get exp002 =>
      'Der Export ist fehlgeschlagen. Es wurde keine gültige PDF-Datei erstellt. Ihr Dokument ist unverändert.';

  @override
  String get exp002Recovery =>
      'Bitte prüfen Sie den freien Speicherplatz und versuchen Sie es erneut.';

  @override
  String exp003(String fields) {
    return 'Der Export wurde gestoppt, weil mindestens ein Feld außerhalb der Seite liegt: $fields. Es wurde keine PDF-Datei erstellt.';
  }

  @override
  String get exp003Recovery =>
      'Bitte verschieben Sie die betroffenen Felder auf die Seite und versuchen Sie es erneut.';

  @override
  String exp004(String fields) {
    return 'Der Export wurde gestoppt, weil ein Zeichen nicht dargestellt werden kann: $fields. Es wurde keine PDF-Datei erstellt.';
  }

  @override
  String get exp004Recovery =>
      'Bitte entfernen Sie das betroffene Zeichen oder ersetzen Sie es und versuchen Sie es erneut.';

  @override
  String get exp005 =>
      'Der Export ist nicht möglich, weil die gespeicherte Originaldatei nicht mehr gelesen werden kann. Ihr bearbeitetes Dokument bleibt erhalten.';

  @override
  String get exp005Recovery =>
      'Bitte importieren Sie das Original erneut und übertragen Sie Ihre Angaben.';

  @override
  String exp006(int page) {
    return 'Der Export wurde gestoppt, weil Seite $page nicht übernommen werden kann. Es wurde keine PDF-Datei erstellt. Seiten werden nicht stillschweigend weggelassen.';
  }

  @override
  String get exp006Recovery =>
      'Bitte prüfen Sie das Original oder importieren Sie es erneut. Andere Seiten und Ihre Eingaben bleiben erhalten.';

  @override
  String get save001Export =>
      'Der Speicherplatz reicht für den Export nicht aus. Es wurde keine gültige PDF-Datei erstellt.';

  @override
  String get save001ExportRecovery =>
      'Bitte geben Sie Speicherplatz frei und versuchen Sie es erneut.';

  @override
  String preExportEmptyFields(int empty) {
    return '$empty Felder sind noch leer. Leere Felder werden nicht ausgefüllt, der Export bleibt möglich.';
  }

  @override
  String preExportUnreviewedSuggestions(int count) {
    return '$count Vorschläge sind noch nicht geprüft. Sie werden nicht in die PDF-Datei übernommen.';
  }

  @override
  String get exportSuccess =>
      'Die PDF-Datei ist fertig und wurde geprüft. Sie können sie ansehen, speichern, teilen oder drucken.';

  @override
  String get previewFooter => 'Vorschau der erzeugten PDF-Datei';

  @override
  String get tpl001 =>
      'Eine Vorlage kann nicht erstellt werden, weil noch keine Felder bestätigt sind oder die Originalseiten nicht lesbar sind.';

  @override
  String get tpl001Recovery =>
      'Bitte prüfen und bestätigen Sie zuerst die Felder.';

  @override
  String get tpl002 =>
      'Die Vorlage konnte nicht gespeichert werden. Bereits vorhandene Vorlagenversionen bleiben unverändert.';

  @override
  String get tpl002Recovery =>
      'Bitte prüfen Sie den freien Speicherplatz und versuchen Sie es erneut.';

  @override
  String get tpl003 =>
      'Die Vorlage konnte nicht geöffnet werden, weil sie unerwartete Eingaben enthält. Es wurden keine Daten geändert.';

  @override
  String get tpl003Recovery =>
      'Bitte versuchen Sie es erneut oder erstellen Sie die Vorlage neu.';

  @override
  String get templateSaveAction => 'Als Vorlage speichern';

  @override
  String get templateLabel => 'Vorlage';

  @override
  String templateVersionLabel(int n, String date) {
    return 'Vorlagenversion $n vom $date';
  }

  @override
  String get templateNewVersionSaved => 'Neue Version gespeichert';

  @override
  String get templateEditorHint =>
      'In einer Vorlage werden nur Felder und Seiten gespeichert – keine Eingaben und keine Unterschriften.';

  @override
  String get date001 =>
      'Bitte geben Sie ein gültiges Datum im Format Tag.Monat.Jahr ein, zum Beispiel 31.12.2025.';

  @override
  String get date002 =>
      'Dieses Datum existiert nicht. Bitte geben Sie ein gültiges Datum im Format Tag.Monat.Jahr ein.';

  @override
  String get date002Recovery => 'Prüfen Sie Tag und Monat.';

  @override
  String get num001 =>
      'Bitte geben Sie eine gültige Zahl ein, zum Beispiel 1234,56.';

  @override
  String get fld001 =>
      'Der Text ist länger als das Feld. Er wurde nicht gekürzt. Der Export wird gestoppt, bis der Text gekürzt oder das Feld vergrößert ist.';

  @override
  String get fld001Recovery =>
      'Bitte kürzen Sie den Text oder vergrößern Sie das Feld.';

  @override
  String get fld002 =>
      'Der bisherige Inhalt passt nicht zum neuen Feldtyp. Er wurde nicht gelöscht und ist weiterhin sichtbar.';

  @override
  String get fld002Recovery =>
      'Bitte prüfen Sie den Inhalt und übernehmen, ändern oder verwerfen Sie ihn bewusst.';

  @override
  String get fld003 =>
      'Zwei Vorschläge überlappen sich. Bitte entscheiden Sie für jeden Vorschlag einzeln, ob er übernommen wird.';

  @override
  String deleteDocumentDialog(String title) {
    return 'Möchten Sie „$title“ wirklich löschen? Gelöscht werden die gespeicherten Seiten, Felder, Eingaben und Unterschriften dieses Dokuments. Andere Dokumente und Vorlagen bleiben erhalten.';
  }

  @override
  String deleteTemplateDialog(String title) {
    return 'Möchten Sie die Vorlage „$title“ mit allen Versionen wirklich löschen? Dokumente, die aus dieser Vorlage erstellt wurden, bleiben unverändert und weiterhin nutzbar.';
  }

  @override
  String deletionConfirmation(String title) {
    return '„$title“ wurde gelöscht. Andere Dokumente und Vorlagen wurden nicht verändert.';
  }

  @override
  String get documentsGroup => 'Dokumente';

  @override
  String get templatesGroup => 'Vorlagen';

  @override
  String get emptyDocuments =>
      'Noch keine Dokumente. Importieren Sie eine gescannte PDF-Datei, um zu beginnen.';

  @override
  String get emptyTemplates =>
      'Noch keine Vorlagen. Speichern Sie ein geprüftes Dokument als Vorlage.';

  @override
  String get importAction => 'PDF importieren';

  @override
  String get statusDraft => 'In Bearbeitung';

  @override
  String get statusExportReady => 'Exportbereit';

  @override
  String get statusUnreadable => 'Nicht lesbar';

  @override
  String get pageAnalysisPending => 'Wartet';

  @override
  String get pageAnalysisPendingHint => 'Analyse ausstehend';

  @override
  String get pageAnalysisAnalyzing => 'Läuft';

  @override
  String get pageAnalysisAnalyzingHint => 'Analyse läuft';

  @override
  String get pageAnalysisComplete => 'Fertig';

  @override
  String get pageAnalysisCompleteHint => 'Analyse abgeschlossen';

  @override
  String get pageAnalysisFailed => 'Fehler';

  @override
  String get pageAnalysisFailedHint => 'Analyse fehlgeschlagen';

  @override
  String fieldCount(int count, int filled) {
    return '$count Felder, $filled ausgefüllt';
  }

  @override
  String lastEdited(String date) {
    return 'Zuletzt bearbeitet: $date';
  }

  @override
  String get reviewAction => 'Felder prüfen';

  @override
  String get fillAction => 'Ausfüllen';

  @override
  String get exportAction => 'PDF exportieren';

  @override
  String get saveNow => 'Jetzt speichern';

  @override
  String get unsavedBadge => 'Nicht gespeichert';

  @override
  String get unsavedRiskBanner =>
      'Ihre letzten Änderungen sind noch nicht dauerhaft gespeichert. Verlassen Sie die App nicht, bis „Gespeichert“ erscheint.';

  @override
  String a11yFieldOverlay(
    String label,
    String type,
    int page,
    String filled,
    String status,
    String conflict,
    String uncertainty,
  ) {
    return 'Feld $label, Typ $type, Seite $page, $filled, $status$conflict$uncertainty';
  }

  @override
  String get a11yFieldValueFilled => 'ausgefüllt';

  @override
  String get a11yFieldValueEmpty => 'leer';

  @override
  String get a11yFieldStatusConfirmed => 'bestätigt';

  @override
  String get a11yFieldStatusSuggestion => 'Vorschlag';

  @override
  String get a11yFieldStatusSelfCreated => 'selbst erstellt';

  @override
  String get a11yFieldConflict => ', Konflikt';

  @override
  String get a11yFieldUncertain => ', unsicher';

  @override
  String a11ySuggestion(String type, String label, int percent) {
    return 'Vorschlag für $type bei $label, Zuverlässigkeit $percent Prozent, nicht bestätigt';
  }

  @override
  String a11yCheckbox(String label, String state) {
    return 'Kontrollkästchen $label, $state';
  }

  @override
  String get a11yCheckboxChecked => 'aktiviert';

  @override
  String get a11yCheckboxUnchecked => 'nicht aktiviert';

  @override
  String a11ySignature(String label, String state) {
    return 'Unterschriftenfeld $label, $state';
  }

  @override
  String get a11ySignatureSigned => 'unterschrieben';

  @override
  String get a11ySignatureUnsigned => 'nicht unterschrieben';

  @override
  String a11yPageNavigation(int page, int count) {
    return 'Seite $page von $count';
  }

  @override
  String a11yZoom(int percent) {
    return 'Vergrößerung $percent Prozent';
  }

  @override
  String get simulatedBanner =>
      'SIMULATED – Entwicklungsansicht mit simulierten Plattformfunktionen. Keine Android-Prüfung.';

  @override
  String get simulatedToken => 'SIMULATED';

  @override
  String get simulatedLogPrefix => '[SIMULATED]';

  @override
  String get simulatedBannerContext =>
      'Entwicklungsansicht: Plattformfunktionen sind simuliert. Ergebnisse gelten nicht als Android-Nachweis.';

  @override
  String get simulatedExportFooterContext =>
      'Simuliertes PDF – kein Produktionsartefakt.';

  @override
  String get simulatedStorageContext =>
      'Simulierter Speicher – keine echte Verschlüsselung.';

  @override
  String get actionUnderstood => 'Verstanden';

  @override
  String get actionRetry => 'Erneut versuchen';

  @override
  String get actionCheckStorage => 'Speicherplatz prüfen';
}
