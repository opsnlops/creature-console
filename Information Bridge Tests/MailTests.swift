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
        #expect(OrderFacts.worldOnly == ["order.tracking"])
    }

    @Test("The source reads a drop folder, casts the orders once, and forgets the mail")
    func sourceCastsOrders() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "mail-tests-\(UUID().uuidString.lowercased())")
        let drop = directory.appending(path: "drop")
        try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)
        let casts = Casts()
        let source = MailSource(
            directory: directory, classifier: MailClassifier(), dropFolder: drop,
            distill: { _ in nil }
        ) { await casts.note($0) }
        let message = mail(
            "mail:1", from: "support@adafruit.com",
            subject: "Your Adafruit order #3312091 has shipped!",
            text: "Tracking number: 1Z999AA10123456784 via UPS")
        try WorldJSON.makeEncoder().encode(message).write(to: drop.appending(path: "0001.json"))
        await source.poll(now: day)
        let events = await casts.events
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.subjectIDs.first?.rawValue == "order:adafruit-3312091" })
        #expect(events.allSatisfy { $0.source.id.rawValue == "bridge:mail" })
        #expect(try FileManager.default.contentsOfDirectory(atPath: drop.path).isEmpty)
        // The same mail again - a redelivered drop - says nothing new.
        try WorldJSON.makeEncoder().encode(message).write(to: drop.appending(path: "0002.json"))
        await source.poll(now: day + 60)
        #expect(await casts.events.count == events.count)
        #expect(await source.orders.count == 1)
    }
}

private actor Casts {
    private(set) var events: [WorldEventEnvelope] = []
    func note(_ event: WorldEventEnvelope) { events.append(event) }
}
