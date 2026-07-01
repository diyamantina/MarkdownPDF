import Foundation

public struct ResumeDocument: Codable, Equatable, Sendable {
    public var basics: Basics
    public var summary: [String]
    public var experience: [Experience]
    public var education: [Education]
    public var projects: [Project]
    public var publications: [Publication]
    public var skills: [SkillGroup]
    public var sections: [Section]

    public init(
        basics: Basics,
        summary: [String] = [],
        experience: [Experience] = [],
        education: [Education] = [],
        projects: [Project] = [],
        publications: [Publication] = [],
        skills: [SkillGroup] = [],
        sections: [Section] = [],
    ) {
        self.basics = basics
        self.summary = summary
        self.experience = experience
        self.education = education
        self.projects = projects
        self.publications = publications
        self.skills = skills
        self.sections = sections
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basics = try container.decode(Basics.self, forKey: .basics)
        summary = try container.decodeArrayIfPresent(String.self, forKey: .summary)
        experience = try container.decodeArrayIfPresent(Experience.self, forKey: .experience)
        education = try container.decodeArrayIfPresent(Education.self, forKey: .education)
        projects = try container.decodeArrayIfPresent(Project.self, forKey: .projects)
        publications = try container.decodeArrayIfPresent(Publication.self, forKey: .publications)
        skills = try container.decodeArrayIfPresent(SkillGroup.self, forKey: .skills)
        sections = try container.decodeArrayIfPresent(Section.self, forKey: .sections)
    }

    public struct Basics: Codable, Equatable, Sendable {
        public var name: String
        public var headline: String?
        public var location: String?
        public var email: String?
        public var phone: String?
        public var links: [Link]

        public init(
            name: String,
            headline: String? = nil,
            location: String? = nil,
            email: String? = nil,
            phone: String? = nil,
            links: [Link] = [],
        ) {
            self.name = name
            self.headline = headline
            self.location = location
            self.email = email
            self.phone = phone
            self.links = links
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            headline = try container.decodeIfPresent(String.self, forKey: .headline)
            location = try container.decodeIfPresent(String.self, forKey: .location)
            email = try container.decodeIfPresent(String.self, forKey: .email)
            phone = try container.decodeIfPresent(String.self, forKey: .phone)
            links = try container.decodeArrayIfPresent(Link.self, forKey: .links)
        }
    }

    public struct Link: Codable, Equatable, Sendable {
        public var label: String
        public var url: String

        public init(label: String, url: String) {
            self.label = label
            self.url = url
        }
    }

    public struct Experience: Codable, Equatable, Sendable {
        public var organization: String
        public var url: String?
        public var location: String?
        public var title: String
        public var start: String
        public var end: String
        public var summary: String?
        public var highlights: [String]
        public var technologies: [String]
        public var projects: [Project]

        public init(
            organization: String,
            url: String? = nil,
            location: String? = nil,
            title: String,
            start: String,
            end: String,
            summary: String? = nil,
            highlights: [String] = [],
            technologies: [String] = [],
            projects: [Project] = [],
        ) {
            self.organization = organization
            self.url = url
            self.location = location
            self.title = title
            self.start = start
            self.end = end
            self.summary = summary
            self.highlights = highlights
            self.technologies = technologies
            self.projects = projects
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            organization = try container.decode(String.self, forKey: .organization)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            location = try container.decodeIfPresent(String.self, forKey: .location)
            title = try container.decode(String.self, forKey: .title)
            start = try container.decode(String.self, forKey: .start)
            end = try container.decode(String.self, forKey: .end)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            highlights = try container.decodeArrayIfPresent(String.self, forKey: .highlights)
            technologies = try container.decodeArrayIfPresent(String.self, forKey: .technologies)
            projects = try container.decodeArrayIfPresent(Project.self, forKey: .projects)
        }
    }

    public struct Education: Codable, Equatable, Sendable {
        public var institution: String
        public var url: String?
        public var degree: String
        public var field: String?
        public var start: String?
        public var end: String?
        public var details: [String]

        public init(
            institution: String,
            url: String? = nil,
            degree: String,
            field: String? = nil,
            start: String? = nil,
            end: String? = nil,
            details: [String] = [],
        ) {
            self.institution = institution
            self.url = url
            self.degree = degree
            self.field = field
            self.start = start
            self.end = end
            self.details = details
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            institution = try container.decode(String.self, forKey: .institution)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            degree = try container.decode(String.self, forKey: .degree)
            field = try container.decodeIfPresent(String.self, forKey: .field)
            start = try container.decodeIfPresent(String.self, forKey: .start)
            end = try container.decodeIfPresent(String.self, forKey: .end)
            details = try container.decodeArrayIfPresent(String.self, forKey: .details)
        }
    }

    public struct Project: Codable, Equatable, Sendable {
        public var name: String
        public var url: String?
        public var role: String?
        public var summary: String?
        public var highlights: [String]
        public var technologies: [String]

        public init(
            name: String,
            url: String? = nil,
            role: String? = nil,
            summary: String? = nil,
            highlights: [String] = [],
            technologies: [String] = [],
        ) {
            self.name = name
            self.url = url
            self.role = role
            self.summary = summary
            self.highlights = highlights
            self.technologies = technologies
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            role = try container.decodeIfPresent(String.self, forKey: .role)
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            highlights = try container.decodeArrayIfPresent(String.self, forKey: .highlights)
            technologies = try container.decodeArrayIfPresent(String.self, forKey: .technologies)
        }
    }

    public struct Publication: Codable, Equatable, Sendable {
        public var title: String
        public var venue: String?
        public var date: String?
        public var url: String?
        public var details: [String]

        public init(
            title: String,
            venue: String? = nil,
            date: String? = nil,
            url: String? = nil,
            details: [String] = [],
        ) {
            self.title = title
            self.venue = venue
            self.date = date
            self.url = url
            self.details = details
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            venue = try container.decodeIfPresent(String.self, forKey: .venue)
            date = try container.decodeIfPresent(String.self, forKey: .date)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            details = try container.decodeArrayIfPresent(String.self, forKey: .details)
        }
    }

    public struct SkillGroup: Codable, Equatable, Sendable {
        public var name: String
        public var items: [String]

        public init(name: String, items: [String] = []) {
            self.name = name
            self.items = items
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            items = try container.decodeArrayIfPresent(String.self, forKey: .items)
        }
    }

    public struct Section: Codable, Equatable, Sendable {
        public var title: String
        public var entries: [Entry]

        public init(title: String, entries: [Entry] = []) {
            self.title = title
            self.entries = entries
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            entries = try container.decodeArrayIfPresent(Entry.self, forKey: .entries)
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var title: String
        public var subtitle: String?
        public var url: String?
        public var details: [String]
        public var technologies: [String]

        public init(
            title: String,
            subtitle: String? = nil,
            url: String? = nil,
            details: [String] = [],
            technologies: [String] = [],
        ) {
            self.title = title
            self.subtitle = subtitle
            self.url = url
            self.details = details
            self.technologies = technologies
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            details = try container.decodeArrayIfPresent(String.self, forKey: .details)
            technologies = try container.decodeArrayIfPresent(String.self, forKey: .technologies)
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeArrayIfPresent<Element: Decodable>(
        _: Element.Type,
        forKey key: Key,
    ) throws -> [Element] {
        try decodeIfPresent([Element].self, forKey: key) ?? []
    }
}
