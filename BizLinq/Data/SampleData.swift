#if DEBUG
import Foundation

/// Seed content for screenshots and SwiftUI previews. Never compiled into
/// Release builds: production content comes from the backend.
enum SampleData {
    /// Next occurrence of a weekday at a given time. weekday: 1 = Sunday ... 7 = Saturday.
    static func next(weekday: Int, hour: Int, minute: Int, weeksOut: Int = 0) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let base = calendar.date(byAdding: .weekOfYear, value: weeksOut, to: now) ?? now
        for offset in 0..<15 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: base) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            guard let candidate = calendar.date(from: components) else { continue }
            if calendar.component(.weekday, from: candidate) == weekday, candidate > now {
                return candidate
            }
        }
        return base
    }

    private static func make(
        title: String,
        group: String,
        category: MeetingCategory,
        tagline: String,
        description: String,
        weekday: Int,
        hour: Int,
        minute: Int,
        weeksOut: Int = 0,
        zip: String,
        venue: String,
        address: String,
        host: String,
        attendees: Int,
        limit: Int? = nil,
        cost: String = "Free",
        virtual: Bool = false
    ) -> Meeting {
        guard let z = ZipDatabase.lookup(zip) else {
            preconditionFailure("SampleData references unknown ZIP: \(zip)")
        }
        return Meeting(
            title: title,
            groupName: group,
            category: category,
            tagline: tagline,
            description: description,
            startsAt: next(weekday: weekday, hour: hour, minute: minute, weeksOut: weeksOut),
            venue: virtual ? "Online" : venue,
            address: virtual ? "Online event - link sent after RSVP" : address,
            city: z.city,
            state: z.state,
            zipCode: z.zip,
            latitude: z.latitude,
            longitude: z.longitude,
            hostName: host,
            attendeeCount: attendees,
            attendeeLimit: limit,
            isVirtual: virtual,
            costDescription: cost
        )
    }

    static var meetings: [Meeting] {
        [
            make(
                title: "Founders Coffee: Downtown NYC",
                group: "NYC Founders Circle",
                category: .businessNetworking,
                tagline: "Weekly coffee for founders, operators, and early employees.",
                description: "A casual weekly meetup for anyone building something. No pitches, no panels - just real conversations about what's working and what isn't. First-timers get a proper intro to the group.",
                weekday: 3, hour: 8, minute: 0,
                zip: "10001",
                venue: "Blue Bottle Coffee",
                address: "1 W 18th St",
                host: "Maya Chen",
                attendees: 34, limit: 50
            ),
            make(
                title: "LA Tech Mixer: Hollywood Edition",
                group: "Silicon Beach Social",
                category: .technology,
                tagline: "Engineers, designers, and PMs over drinks.",
                description: "Our monthly mixer brings together LA's tech scene. Bring a friend, bring a hiring need, or just bring yourself. Name tags include what you're working on so conversations start easy.",
                weekday: 5, hour: 18, minute: 30,
                zip: "90028",
                venue: "The Rooftop at Mama Shelter",
                address: "6500 Selma Ave",
                host: "Devon Park",
                attendees: 87, limit: 120, cost: "$10 at the door"
            ),
            make(
                title: "Chicago Real Estate Roundtable",
                group: "Windy City Investors",
                category: .realEstate,
                tagline: "Lunch deal review with active local investors.",
                description: "Every week one member brings a live deal and the room underwrites it together. Wholesalers, agents, lenders, and buy-and-hold investors all welcome. Lunch is available for purchase.",
                weekday: 4, hour: 12, minute: 0,
                zip: "60601",
                venue: "Revival Food Hall",
                address: "125 S Clark St",
                host: "Marcus Webb",
                attendees: 42, limit: 60
            ),
            make(
                title: "Austin SaaS Sales Breakfast",
                group: "ATX Revenue Collective",
                category: .businessNetworking,
                tagline: "SDRs, AEs, and founders swapping what converts.",
                description: "A tactical breakfast for people who carry a quota or want to. Each week covers one topic - outbound, discovery, demos, or negotiation - with open Q&A. Coffee and tacos provided.",
                weekday: 6, hour: 8, minute: 30,
                zip: "78701",
                venue: "Hearth & Soul",
                address: "800 Brazos St",
                host: "Priya Nair",
                attendees: 28, limit: 40
            ),
            make(
                title: "Women in Business Luncheon",
                group: "Miami Women Who Lead",
                category: .businessNetworking,
                tagline: "Monthly luncheon with a featured founder story.",
                description: "Join 60+ women building businesses across South Florida. This month's featured guest scaled a hospitality group from one cafe to twelve locations. Includes lunch and structured networking.",
                weekday: 6, hour: 12, minute: 0, weeksOut: 1,
                zip: "33139",
                venue: "The Betsy Hotel",
                address: "1440 Ocean Dr",
                host: "Sofia Delgado",
                attendees: 61, limit: 80, cost: "$25 includes lunch"
            ),
            make(
                title: "Young Professionals After Work",
                group: "Denver NextGen Network",
                category: .businessNetworking,
                tagline: "Under-40 professionals across every industry.",
                description: "Wind down the week with Denver's under-40 crowd across tech, finance, healthcare, and more. Rotating venues downtown. Your first drink ticket is on the group sponsors.",
                weekday: 5, hour: 17, minute: 30,
                zip: "80202",
                venue: "Terminal Bar, Union Station",
                address: "1701 Wynkoop St",
                host: "Jake Morrison",
                attendees: 55, limit: 100
            ),
            make(
                title: "Seattle Startup Pitch Night",
                group: "Emerald City Entrepreneurs",
                category: .businessNetworking,
                tagline: "Five founders pitch, the room votes, winner gets perks.",
                description: "Five early-stage founders get five minutes each, then audience Q&A. Friendly crowd of angels, operators, and engineers. Founders can apply to pitch at the door if a slot opens.",
                weekday: 4, hour: 18, minute: 0,
                zip: "98101",
                venue: "Galvanize Seattle",
                address: "111 S Jackson St",
                host: "Lena Kowalski",
                attendees: 73, limit: 90, cost: "$5 at the door"
            ),
            make(
                title: "Finance & Investing Dinner",
                group: "Boston Capital Club",
                category: .businessNetworking,
                tagline: "Public markets, private deals, and portfolio talk.",
                description: "A monthly dinner for investors, advisors, and finance professionals. Off-the-record Chatham House rules so people speak freely. Separate checks; RSVP required for the headcount.",
                weekday: 3, hour: 19, minute: 0, weeksOut: 1,
                zip: "02108",
                venue: "Yvonne's",
                address: "2 Winter Pl",
                host: "Robert Hale",
                attendees: 22, limit: 30
            ),
            make(
                title: "SF AI Builders Meetup",
                group: "Bay Area AI Builders",
                category: .technology,
                tagline: "Live demos from people shipping AI products.",
                description: "Three live demos, zero slide decks. If you're building with LLMs, agents, or applied ML, come show it or come learn. Researchers, founders, and the simply curious all welcome.",
                weekday: 2, hour: 18, minute: 30,
                zip: "94103",
                venue: "South Park Commons",
                address: "156 2nd St",
                host: "Aisha Bello",
                attendees: 118, limit: 150
            ),
            make(
                title: "Nashville Small Biz Coffee",
                group: "Music City Main Street",
                category: .businessNetworking,
                tagline: "Saturday coffee for owners and side-hustlers.",
                description: "An easy Saturday meetup for small business owners, freelancers, and anyone thinking about starting something. Kids welcome. We do quick intros then open networking.",
                weekday: 7, hour: 9, minute: 0,
                zip: "37203",
                venue: "Frothy Monkey",
                address: "2509 12th Ave S",
                host: "Caleb Turner",
                attendees: 19
            ),
            make(
                title: "National Referral Exchange (Virtual)",
                group: "Referral Nation",
                category: .businessNetworking,
                tagline: "Join from anywhere: 60-second intros, real referrals.",
                description: "Our weekly national call runs like clockwork: 60-second introductions, breakout rooms by industry, and a referral round at the end. Open to all US time zones. Camera on, coffee ready.",
                weekday: 4, hour: 13, minute: 0,
                zip: "30301",
                venue: "Online",
                address: "Online event - link sent after RSVP",
                host: "Dana Whitfield",
                attendees: 140, limit: 200,
                virtual: true
            ),
            make(
                title: "Dallas Commercial RE Breakfast",
                group: "DFW Deal Makers",
                category: .realEstate,
                tagline: "Brokers, developers, and capital partners.",
                description: "A biweekly breakfast focused on DFW commercial deals - office, retail, industrial, and land. Each table has a host to make sure nobody eats alone. Parking validated.",
                weekday: 3, hour: 7, minute: 30, weeksOut: 1,
                zip: "75201",
                venue: "The Joule",
                address: "1530 Main St",
                host: "Tom Okafor",
                attendees: 47, limit: 70, cost: "$15 includes breakfast"
            ),
        ]
    }
}
#endif
