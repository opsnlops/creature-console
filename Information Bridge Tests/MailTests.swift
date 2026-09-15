import Foundation
import Testing
import WorldCore

@testable import Information_Bridge

@Suite("The mail, as orders")
struct MailTests {
    private let day = Date(timeIntervalSince1970: 1_789_500_000)

    private func mail(
        _ id: String, from: String, subject: String, text: String = "", daysLater: Double = 0
    ) -> MailMessage {
        MailMessage(
            identifier: id, from: from, subject: subject,
            date: day.addingTimeInterval(daysLater * 86_400), text: text)
    }

    @Test("Sender and subject decide what a mail is; strangers are irrelevant")
    func classifies() {
        let classifier = MailClassifier()
        #expect(
            classifier.classify(
                mail(
                    "1", from: "Adafruit <orders@adafruit.com>",
                    subject: "Your Adafruit order #3312091 has shipped!"))
                == .shipping)
        #expect(
            classifier.classify(
                mail(
                    "2", from: "auto-confirm@amazon.com",
                    subject: "Your Amazon.com order of Servo Kit ×4"))
                == .order)
        #expect(
            classifier.classify(
                mail(
                    "3", from: "mcinfonotify@ups.com",
                    subject: "UPS Update: Package Scheduled for Delivery Today"))
                == .shipping)
        #expect(
            classifier.classify(mail("4", from: "polly@example.com", subject: "hey, running late"))
                == .irrelevant)
        #expect(
            classifier.classify(
                mail(
                    "5", from: "noreply@coupevilledental.com",
                    subject: "Your appointment is confirmed"))
                == .appointment)
        #expect(
            classifier.classify(
                mail("6", from: "deals@amazon.com", subject: "Deals you might like")) == .irrelevant
        )
    }

    @Test("Numbers and statuses have a shape the regexes find; item names come off the subject")
    func reads() {
        let shipped = MailReader.read(
            mail(
                "1", from: "Adafruit Industries <support@adafruit.com>",
                subject: "Your Adafruit order #3312091 has shipped!",
                text: "Tracking number: 1Z999AA10123456784 via UPS. Items: Servo Kit ×4"),
            kind: .shipping)
        #expect(shipped.merchant == "adafruit")
        #expect(shipped.orderNumber == "3312091")
        #expect(shipped.tracking == "1Z999AA10123456784")
        #expect(shipped.carrier == "UPS")
        #expect(shipped.status == .shipped)

        let amazon = MailReader.read(
            mail(
                "2", from: "\"Amazon.com\" <shipment-tracking@amazon.com>",
                subject: "Shipped: Servo Kit ×4",
                text: "Order # 112-3456789-0123456 arriving Tuesday"),
            kind: .shipping)
        #expect(amazon.merchant == "amazon")
        #expect(amazon.items == ["Servo Kit ×4"])
        #expect(amazon.orderNumber == "112-3456789-0123456")

        let today = MailReader.read(
            mail(
                "3", from: "mcinfonotify@ups.com", subject: "UPS Update: Package Out for Delivery",
                text: "1Z999AA10123456784"),
            kind: .shipping)
        #expect(today.status == .outForDelivery)
        #expect(today.carrier == "UPS")
        #expect(today.tracking == "1Z999AA10123456784")
    }

    @Test(
        "Mails about one order fold into one entity; a carrier's tracking joins the merchant's order"
    )
    func orderBook() {
        var book = OrderBook()
        let classifier = MailClassifier()
        let placed = mail(
            "a", from: "orders@adafruit.com", subject: "Thanks for your order #3312091",
            text: "Order #3312091. Servo Kit ×4, Total $48.20")
        let shipped = mail(
            "b", from: "support@adafruit.com", subject: "Your Adafruit order #3312091 has shipped!",
            text: "Tracking number: 1Z999AA10123456784 via UPS", daysLater: 1)
        let out = mail(
            "c", from: "mcinfonotify@ups.com", subject: "UPS Update: Package Out for Delivery",
            text: "Tracking Number: 1Z999AA10123456784", daysLater: 3)
        for message in [placed, shipped, out] {
            var reading = MailReader.read(message, kind: classifier.classify(message))
            if message.identifier == "a" {
                // What the on-device model adds, when the subject did not name the items.
                reading = reading.filled(
                    with: CommerceReading(
                        merchant: "Adafruit", orderNumber: "3312091", trackingNumber: "",
                        items: ["Servo Kit ×4"], total: "$48.20", expectedDelivery: ""))
            }
            book.apply(reading, at: message.date)
        }
        #expect(book.orders.count == 1)
        let order = try! #require(book.orders.values.first)
        #expect(order.entityID.rawValue == "order:adafruit-3312091")
        #expect(order.merchant == "adafruit")
        #expect(order.items == ["Servo Kit ×4"])
        #expect(order.tracking == "1Z999AA10123456784")
        #expect(order.carrier == "UPS")
        #expect(order.status == .outForDelivery)
        #expect(order.total == "$48.20")
        #expect(order.placed == day)
        #expect(order.description == "Servo Kit ×4")
        let wanted = try! #require(book.wanted.values.first)
        #expect(wanted.facts["order.status"] == .string("out_for_delivery"))
        #expect(wanted.facts["order.for"] == .string("person:april"))
        #expect(wanted.facts["order.items"] == .array([.string("Servo Kit ×4")]))
        #expect(wanted.validUntil == nil)
        #expect(OrderFacts.worldOnly == ["order.tracking", "order.updated_at"])
        #expect(wanted.facts["order.updated_at"] != nil)
        #expect(OrderFacts.tidyTotal("21.689999999999998 USD") == "$21.69")
    }

    @Test("A carrier's window becomes a day, judged from the day the mail came")
    func expectedBecomesADay() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let june7 = Date(timeIntervalSince1970: 1_780_876_800)  // Sunday, June 7, 2026, Pacific
        func resolve(_ text: String) -> String {
            OrderFacts.resolveExpected(text, mailedOn: june7, zone: zone)
        }
        #expect(resolve("Arriving tomorrow") == "June 8, 2026")
        #expect(resolve("Delivered today") == "June 7, 2026")
        #expect(resolve("by Thursday, 9 PM") == "June 11, 2026")
        #expect(resolve("Sunday") == "June 14, 2026")
        #expect(resolve("Monday, September 16") == "September 16, 2026")
        #expect(resolve("Jan 4") == "January 4, 2027")
        #expect(resolve("soon") == "soon (as of June 7, 2026)")
    }

    @Test("A delivered order has no window left; every order says when the mail last spoke")
    func expectedDropsOnceDelivered() {
        var book = OrderBook()
        book.apply(
            MailReader.read(
                mail(
                    "s", from: "support@adafruit.com",
                    subject: "Your Adafruit order #3312091 has shipped!",
                    text: "Tracking number: 1Z999AA10123456784 via UPS"),
                kind: .shipping
            ).filled(
                with: CommerceReading(
                    merchant: "", orderNumber: "", trackingNumber: "Ph5FnJ4KZ", items: [],
                    total: "", expectedDelivery: "Arriving tomorrow")),
            at: day)
        var wanted = try! #require(book.wanted.values.first)
        #expect(wanted.facts["order.expected"] == .string(OrderFacts.day(day + 86_400)))
        #expect(wanted.facts["order.last_heard"] == .string(OrderFacts.day(day)))
        #expect(wanted.facts["order.tracking"] == .string("1Z999AA10123456784"))
        book.apply(
            MailReader.read(
                mail(
                    "d", from: "mcinfonotify@ups.com", subject: "UPS Update: Package Delivered",
                    text: "Tracking Number: 1Z999AA10123456784", daysLater: 2),
                kind: .shipping),
            at: day + 2 * 86_400)
        wanted = try! #require(book.wanted.values.first)
        #expect(wanted.facts["order.status"] == .string("delivered"))
        #expect(wanted.facts["order.expected"] == nil)
        #expect(wanted.facts["order.last_heard"] == .string(OrderFacts.day(day + 2 * 86_400)))
        #expect(!MailReader.looksLikeTracking("Ph5FnJ4KZ"))
        #expect(MailReader.looksLikeTracking("381467870711"))
    }

    @Test("A carrier's mail takes no order number, not even from the model")
    func carriersKeyByTracking() {
        let fedex = MailReader.read(
            mail(
                "f", from: "FedEx Delivery Manager <TrackingUpdates@fedex.com>",
                subject: "Your shipment is on the way 381467870711",
                text: "Reference: S931R234. Order number S931R234."),
            kind: .shipping)
        #expect(fedex.orderNumber == nil)
        #expect(fedex.tracking == "381467870711")
        let filled = fedex.filled(
            with: CommerceReading(
                merchant: "FedEx", orderNumber: "S931R234", trackingNumber: "", items: [],
                total: "", expectedDelivery: ""))
        #expect(filled.orderNumber == nil)
        var book = OrderBook()
        book.apply(filled, at: day)
        #expect(book.orders.keys.first == "fedex-381467870711")
    }

    @Test("Item names are tidied: bidi marks, ellipses, Amazon's tails, and placeholders")
    func tidiesItems() {
        #expect(
            MailReading.tidy("\u{2066}2\u{2069} \"MiraLAX, Laxative Powder,...")
                == "2 MiraLAX, Laxative Powder")
        #expect(
            MailReading.tidy("Amazon Basics Wired QWERTY...\" and \u{2066}1\u{2069} more item")
                == "Amazon Basics Wired QWERTY")
        #expect(MailReading.isPlaceholder("Item"))
        #expect(MailReading.isPlaceholder("1 Kitchen item"))
        #expect(!MailReading.isPlaceholder("Servo Kit ×4"))
    }

    @Test("The source reads its accounts, casts the orders once, and forgets the mail")
    func sourceCastsOrders() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "mail-tests-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let casts = Casts()
        let message = mail(
            "mail:1", from: "support@adafruit.com",
            subject: "Your Adafruit order #3312091 has shipped!",
            text: "Tracking number: 1Z999AA10123456784 via UPS")
        let source = MailSource(
            directory: directory, classifier: MailClassifier(),
            fetch: { _ in [message] },  // the same mail every time, as an account would answer
            distill: { _ in nil }
        ) { await casts.note($0) }
        await source.poll(now: day)
        let events = await casts.events
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.subjectIDs.first?.rawValue == "order:adafruit-3312091" })
        #expect(events.allSatisfy { $0.source.id.rawValue == "bridge:mail" })
        // The same mail again says nothing new.
        await source.poll(now: day + 60)
        #expect(await casts.events.count == events.count)
        #expect(await source.orders.count == 1)
        #expect(await source.status.state == .on)
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}
