import Foundation
import Testing
@testable import Siigil

private let rome = TimeZone(identifier: "Europe/Rome")!
private let date: Date = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = rome
    return c.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 16, minute: 5))!
}()

@Test func clockStringEnglish() {
    #expect(clockString(date, locale: Locale(identifier: "en"), timeZone: rome) == "Sat 19 Sep 16:05")
}

@Test func clockStringItalianCapitalized() {
    #expect(clockString(date, locale: Locale(identifier: "it"), timeZone: rome) == "Sab 19 Set 16:05")
}

@Test func wavesByLevel() {
    #expect([0, 1, 33, 34, 66, 67, 100].map(waves) == [0, 1, 1, 2, 2, 3, 3])
}

@Test func clockStringCustomAndEmptyFormat() {
    #expect(clockString(date, format: "HH:mm", locale: Locale(identifier: "en"), timeZone: rome) == "16:05")
    #expect(clockString(date, format: "", locale: Locale(identifier: "en"), timeZone: rome) == "Sat 19 Sep 16:05")   // vuoto = default
    // Gli spazi all'inizio e alla fine non contano: nel blocco unito si vedrebbero come un vuoto accanto all'orologio.
    #expect(clockString(date, format: " HH:mm ", locale: Locale(identifier: "en"), timeZone: rome) == "16:05")
}

// Maiuscola solo all'inizio di ogni parola, il resto com'è: "PM" e i fusi ("CEST") non diventano "Pm" e "Cest" (27/9).
@Test func clockStringKeepsTheRestOfEachWord() {
    #expect(clockString(date, format: "h:mm a", locale: Locale(identifier: "en"), timeZone: rome) == "4:05 PM")
    #expect(clockString(date, format: "EEEE HH:mm zzz", locale: Locale(identifier: "en_GB"), timeZone: rome) == "Saturday 16:05 CEST")
}

