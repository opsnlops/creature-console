import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("Appointments, from the mail")
struct AppointmentTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!
    private let house = try! EntityID(validating: "house:aprils-nest")
    // Thursday 2026-09-10 09:00 PDT: the reminder came five days ahead.
    private let mailed = Date(timeIntervalSince1970: 1_789_056_000)

    private var reminder: MailMessage {
        MailMessage(
            identifier: "mail:pest", from: "Whidbey Pest Control <whidbeypestcontrol@gmail.com>",
            subject: "Appointment Reminder", date: mailed,
            text: """
                Scheduled visit reminder by Whidbey Pest Control - Sep 15, 2026

                Hi April White,

                Just a friendly reminder that we have an upcoming appointment.

                Sep 15, 2026
                Monthly Service
                12 Mulberry Ln / Clinton, Wa 98236
                """)
    }

    @Test("Days and windows as mail writes them, judged from the day the mail came")
    func datesAndWindows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        func day(_ text: String) -> DateComponents? {
            MailDates.day(in: text, mailedOn: mailed, zone: pacific).map {
                calendar.dateComponents([.year, .month, .day], from: $0)
            }
        }
        #expect(day("Sep 15, 2026") == DateComponents(year: 2026, month: 9, day: 15))
        #expect(day("Thursday, September 17") == DateComponents(year: 2026, month: 9, day: 17))
        #expect(day("9/18") == DateComponents(year: 2026, month: 9, day: 18))
        #expect(day("Jan 4") == DateComponents(year: 2027, month: 1, day: 4))
        #expect(day("tomorrow") == DateComponents(year: 2026, month: 9, day: 11))
        #expect(day("Monday") == DateComponents(year: 2026, month: 9, day: 14))
        #expect(day("Thursday") == DateComponents(year: 2026, month: 9, day: 10))  // today
        #expect(day("Tuesday, November 17th") == DateComponents(year: 2026, month: 11, day: 17))
        #expect(day("October 1st") == DateComponents(year: 2026, month: 10, day: 1))
        // A day with no month is the next such day: ahead this month, else next month.
        #expect(day("Re: 16th Cleaning") == DateComponents(year: 2026, month: 9, day: 16))
        #expect(day("the 3rd") == DateComponents(year: 2026, month: 10, day: 3))
        #expect(day("soon") == nil)

        #expect(MailDates.window(in: "8:00 AM - 10:00 AM")! == (480, 600))
        #expect(MailDates.window(in: "between 8 and 10 am")! == (480, 600))
        #expect(MailDates.window(in: "at 2:30 PM")! == (870, 930))
        #expect(MailDates.window(in: "at 2")! == (840, 900))
        #expect(MailDates.window(in: "") == nil)
    }

    @Test("The pest control reminder becomes a visitor on the house for the day")
    func reminderBecomesAVisitor() {
        let reading = AppointmentReading(
            business: "Whidbey Pest Control", service: "Monthly Service", dateWords: "Sep 15, 2026",
            timeWords: "", atAprilsHome: false, isCancellation: false)
        // The model copied the date from the mail, so the reading stands.
        #expect(AppointmentDistiller.isSupported(reading, by: reminder))
        #expect(
            !AppointmentDistiller.isSupported(
                AppointmentReading(
                    business: "Whidbey Pest Control", service: "",
                    dateWords: "Tuesday, September 22",
                    timeWords: "", atAprilsHome: true, isCancellation: false), by: reminder))
        // The mail prints April's street: at home, whatever the model guessed.
        let atHome = AppointmentFacts.isAtHome(reminder, homeStreets: ["12 mulberry ln"])
        #expect(atHome == true)
        #expect(AppointmentFacts.isAtHome(reminder, homeStreets: []) == nil)
        // No street in the mail is no evidence, not a denial: the model's reading stands.
        #expect(AppointmentFacts.isAtHome(reminder, homeStreets: ["1 other st"]) == nil)

        var book = AppointmentBook()
        let appointment = book.apply(reading, mailedOn: mailed, zone: pacific, atHome: atHome)!
        #expect(appointment.entityID.rawValue == "event:mail-whidbeypestcontrol-20260915")
        #expect(appointment.window == nil)
        let wanted = book.wanted(zone: pacific, house: house)
        let event = wanted["appointment:\(appointment.key)"]!
        #expect(event.entityID == appointment.entityID)
        #expect(event.facts["calendar.title"] == .string("Monthly Service (Whidbey Pest Control)"))
        #expect(event.facts["calendar.when"] == .string("Tuesday, September 15 (time not given)"))
        #expect(event.facts["calendar.location"] == .string("home"))
        #expect(event.facts["calendar.starts_at"] == .string("2026-09-15T15:00:00.000Z"))
        #expect(event.facts["calendar.ends_at"] == .string("2026-09-16T01:00:00.000Z"))
        let visitor = wanted["appointment:\(appointment.key):visitor"]!
        #expect(visitor.entityID == house)
        #expect(
            visitor.facts["visitor.expected"]
                == .string(
                    "Whidbey Pest Control for Monthly Service, Tuesday, September 15 (time not given)"
                ))
        #expect(visitor.validUntil == WorldJSON.date(from: "2026-09-16T01:00:00.000Z")! + 2 * 3_600)

        // The same appointment, cancelled by a later mail: nothing held.
        var cancelled = reading
        cancelled.isCancellation = true
        book.apply(cancelled, mailedOn: mailed + 86_400, zone: pacific, atHome: true)
        #expect(book.wanted(zone: pacific, house: house).isEmpty)
        // A week after the day, it is let go.
        book.forgetPast(now: mailed + 14 * 86_400, zone: pacific)
        #expect(book.appointments.isEmpty)
    }

    @Test("A reply is read as a thread: the sender's words, then April's, never the attribution")
    func repliesAreThreads() {
        let reply = MailMessage(
            identifier: "mail:tamara", from: "Tamara <tamara@example.com>",
            subject: "Re: Sep 16th Cleaning", date: mailed,
            text: """
                Hi April! Thank you so much for letting us know.

                Best, Tamara
                Quality Cleaning, Etc

                On Sep 15, 2026, at 7:05 PM, April White <april@example.com> wrote:

                > Hi Tamara!
                >
                > I have a doctor's appointment on the mainland on the 16th, so I might not be home when the crew arrives. I'll leave the front door unlocked when I leave.
                >
                > April
                """)
        let (latest, quoted) = MailText.parts(of: reply.text)
        #expect(latest.hasPrefix("Hi April!"))
        #expect(latest.hasSuffix("Quality Cleaning, Etc"))
        #expect(quoted.hasPrefix("Hi Tamara!"))
        #expect(quoted.contains("front door unlocked"))
        #expect(!quoted.contains("7:05 PM"))
        let prompt = AppointmentDistiller.prompt(for: reply)
        #expect(prompt.contains("The latest message, from Tamara:"))
        #expect(prompt.contains("written earlier by April:"))
        #expect(!prompt.contains("7:05"))
        // A date only on the attribution line does not support a reading.
        #expect(
            !AppointmentDistiller.isSupported(
                AppointmentReading(
                    business: "", service: "", dateWords: "Sep 15, 2026", timeWords: "7:05 PM",
                    atAprilsHome: false, isCancellation: false), by: reply))
        #expect(
            AppointmentDistiller.isSupported(
                AppointmentReading(
                    business: "", service: "Cleaning", dateWords: "Sep 16th", timeWords: "",
                    atAprilsHome: true, isCancellation: false), by: reply))
        // The place question's evidence must be about the house, not any place at all.
        #expect(
            AppointmentDistiller.houseWords.contains {
                "not be home when the crew arrives".contains($0)
            })
        #expect(!AppointmentDistiller.houseWords.contains { "on the mainland".contains($0) })
        // No reply at all: everything is the latest part.
        #expect(MailText.parts(of: "Just the one message").quoted.isEmpty)
    }

    @Test("A person's mail names no business; the sender is who is coming")
    func senderStandsInForBusiness() {
        #expect(MailReader.displayName(of: "Maria Lopez <maria@example.com>") == "Maria Lopez")
        #expect(
            MailReader.displayName(of: "\"Lopez, Maria\" <maria@example.com>") == "Lopez, Maria")
        #expect(MailReader.displayName(of: "maria@example.com") == "maria")
        #expect(MailReader.address(of: "Maria Lopez <Maria@Example.com>") == "maria@example.com")
    }

    @Test("An appointment April goes to is an event, not a visitor")
    func awayAppointmentsAreEventsOnly() {
        var book = AppointmentBook()
        let reading = AppointmentReading(
            business: "Coupeville Dental", service: "cleaning", dateWords: "Thursday, September 17",
            timeWords: "2:30 PM", atAprilsHome: false, isCancellation: false)
        let appointment = book.apply(reading, mailedOn: mailed, zone: pacific, atHome: false)!
        #expect(appointment.window! == (870, 930))
        let wanted = book.wanted(zone: pacific, house: house)
        #expect(wanted.count == 1)
        #expect(
            wanted.values.first?.facts["calendar.when"]
                == .string("Thursday, September 17, 2:30 PM–3:30 PM"))
        #expect(wanted.values.first?.facts["calendar.location"] == nil)
    }
}
