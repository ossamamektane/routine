import Foundation

struct SymbolChoice: Hashable {
    var symbol: String
    var color: ItemColor
}

enum Symbols {
    /// The icon picker. All are standard SF Symbols available on iOS 17.
    static let all: [String] = [
        "checkmark", "sun.max.fill", "sunrise.fill", "moon.fill", "moon.stars.fill", "bed.double.fill",
        "drop.fill", "pills.fill", "cross.case.fill", "stethoscope", "heart.fill", "brain.head.profile",
        "figure.walk", "figure.run", "figure.mind.and.body", "dumbbell.fill", "bicycle", "sparkles",
        "shower.fill", "bathtub.fill", "scissors", "tshirt.fill", "washer.fill", "trash.fill",
        "fork.knife", "cup.and.saucer.fill", "cart.fill", "bag.fill", "basket.fill", "gift.fill",
        "mug.fill", "wineglass.fill", "takeoutbag.and.cup.and.straw.fill", "carrot.fill", "smoke.fill", "dollarsign.circle.fill",
        "house.fill", "bolt.fill", "wifi", "iphone", "phone.fill", "tv.fill",
        "play.rectangle.fill", "music.note", "headphones", "gamecontroller.fill", "book.fill", "graduationcap.fill",
        "briefcase.fill", "laptopcomputer", "envelope.fill", "doc.text.fill", "square.and.pencil", "paintbrush.fill",
        "creditcard.fill", "banknote.fill", "building.columns.fill", "shield.fill", "lock.fill", "key.fill",
        "car.fill", "fuelpump.fill", "tram.fill", "airplane", "pawprint.fill", "leaf.fill",
        "person.2.fill", "calendar", "alarm.fill", "star.fill", "flame.fill", "wrench.and.screwdriver.fill",
    ]

    /// Keywords (lowercase, without accents) in English, French and Arabic, most specific first.
    static let rules: [(words: [String], choice: SymbolChoice)] = [
        (["plant", "plante", "arroser", "jardin", "garden", "نبات", "زرع"], SymbolChoice(symbol: "leaf.fill", color: .green)),
        (["electric", "power bill", "electricite", "edf", "كهرباء"], SymbolChoice(symbol: "bolt.fill", color: .yellow)),
        (["energy", "energie", "red bull", "redbull", "طاقة"], SymbolChoice(symbol: "bolt.fill", color: .green)),
        (["internet", "wifi", "wi-fi", "fibre", "box", "انترنت", "إنترنت"], SymbolChoice(symbol: "wifi", color: .blue)),
        (["phone bill", "mobile", "forfait", "cell", "هاتف", "جوال", "موبايل"], SymbolChoice(symbol: "iphone", color: .green)),
        (["rent", "loyer", "mortgage", "hypotheque", "credit immo", "إيجار", "ايجار", "كراء"], SymbolChoice(symbol: "house.fill", color: .orange)),
        (["netflix", "spotify", "disney", "youtube", "prime", "hbo", "deezer", "canal", "streaming", "apple tv", "apple music"], SymbolChoice(symbol: "play.rectangle.fill", color: .red)),
        (["subscription", "abonnement", "اشتراك"], SymbolChoice(symbol: "repeat", color: .indigo)),
        (["insurance", "assurance", "mutuelle", "تأمين", "تامين"], SymbolChoice(symbol: "shield.fill", color: .indigo)),
        (["fuel", "petrol", "gas station", "essence", "carburant", "بنزين", "وقود"], SymbolChoice(symbol: "fuelpump.fill", color: .orange)),
        (["car ", "voiture", "parking", "garage", "سيارة"], SymbolChoice(symbol: "car.fill", color: .blue)),
        (["gym", "workout", "exercise", "training", "sport", "muscu", "entrainement", "رياضة", "تمرين", "تمارين"], SymbolChoice(symbol: "dumbbell.fill", color: .orange)),
        (["running", "jogging", "footing", "جري"], SymbolChoice(symbol: "figure.run", color: .orange)),
        (["walk", "marche", "promenade", "مشي"], SymbolChoice(symbol: "figure.walk", color: .green)),
        (["bike", "cycling", "velo", "دراجة"], SymbolChoice(symbol: "bicycle", color: .green)),
        (["yoga", "stretch", "etirement", "يوغا", "تمدد"], SymbolChoice(symbol: "figure.mind.and.body", color: .purple)),
        (["meditat", "breath", "respir", "تأمل", "تنفس"], SymbolChoice(symbol: "brain.head.profile", color: .indigo)),
        (["medic", "pill", "vitamin", "tablet", "medicament", "cachet", "pilule", "traitement", "دواء", "حبوب", "فيتامين", "علاج"], SymbolChoice(symbol: "pills.fill", color: .red)),
        (["doctor", "dentist", "therap", "medecin", "dentiste", "rendez-vous", "طبيب", "دكتور", "موعد"], SymbolChoice(symbol: "stethoscope", color: .teal)),
        (["haircut", "barber", "hair", "coiffeur", "cheveux", "حلاق", "شعر"], SymbolChoice(symbol: "scissors", color: .purple)),
        (["teeth", "floss", "tooth", "dents", "brosse", "أسنان", "اسنان"], SymbolChoice(symbol: "sparkles", color: .cyan)),
        (["shower", "bath", "douche", "bain", "استحمام", "حمام"], SymbolChoice(symbol: "shower.fill", color: .blue)),
        (["laundry", "washing", "lessive", "linge", "غسيل", "ملابس"], SymbolChoice(symbol: "washer.fill", color: .blue)),
        (["trash", "garbage", "recycl", "poubelle", "ordures", "قمامة", "نفايات", "زبالة"], SymbolChoice(symbol: "trash.fill", color: .gray)),
        (["clean", "vacuum", "tidy", "menage", "nettoy", "aspirateur", "ranger", "تنظيف", "ترتيب"], SymbolChoice(symbol: "sparkles", color: .mint)),
        (["grocer", "shopping", "supermarket", "courses", "supermarche", "تسوق", "بقالة", "مشتريات"], SymbolChoice(symbol: "cart.fill", color: .green)),
        (["coffe", "cafe", " tea ", "starbucks", "قهوة", "شاي"], SymbolChoice(symbol: "cup.and.saucer.fill", color: .brown)),
        (["cook", "dinner", "lunch", "breakfast", "meal", "dish", "cuisine", "repas", "diner", "dejeuner", "vaisselle", "طبخ", "غداء", "عشاء", "فطور", "صحون"], SymbolChoice(symbol: "fork.knife", color: .orange)),
        (["egg", "oeuf", "milk", "lait", "bread", "baguette", "fruit", "vegetable", "legume", "بيض", "حليب", "خبز", "خضر", "فواكه"], SymbolChoice(symbol: "basket.fill", color: .orange)),
        (["beer", "biere", "بيرة"], SymbolChoice(symbol: "mug.fill", color: .yellow)),
        (["wine", "alcohol", "alcool", "نبيذ"], SymbolChoice(symbol: "wineglass.fill", color: .purple)),
        (["cigarette", "cigar", "smok", "tobacco", "tabac", "clope", "vape", "سجائر", "سيجارة", "دخان", "تدخين"], SymbolChoice(symbol: "smoke.fill", color: .gray)),
        (["weed", "cannabis", "chira", "حشيش"], SymbolChoice(symbol: "leaf.fill", color: .mint)),
        (["water", "drink", "hydrat", "eau", "boire", "ماء", "مياه", "اشرب"], SymbolChoice(symbol: "drop.fill", color: .cyan)),
        (["sleep", "bedtime", "go to bed", "dormir", "coucher", "نوم", "النوم"], SymbolChoice(symbol: "bed.double.fill", color: .indigo)),
        (["make the bed", "faire le lit", "سرير"], SymbolChoice(symbol: "bed.double.fill", color: .teal)),
        (["wake", "morning", "reveil", "matin", "استيقاظ", "صباح"], SymbolChoice(symbol: "sunrise.fill", color: .orange)),
        (["pray", "prayer", "priere", "quran", "coran", "صلاة", "قرآن", "قران", "أذكار", "اذكار"], SymbolChoice(symbol: "moon.stars.fill", color: .indigo)),
        (["read", "book", "lire", "lecture", "livre", "قراءة", "كتاب"], SymbolChoice(symbol: "book.fill", color: .brown)),
        (["study", "homework", "revis", "etud", "devoirs", "cours", "دراسة", "واجب", "مراجعة"], SymbolChoice(symbol: "graduationcap.fill", color: .indigo)),
        (["journal", "diary", "write", "ecrire", "كتابة", "مذكرات"], SymbolChoice(symbol: "square.and.pencil", color: .yellow)),
        (["email", "inbox", "mail", "courriel", "بريد"], SymbolChoice(symbol: "envelope.fill", color: .blue)),
        (["call", "appeler", "telephoner", "اتصال", "اتصل"], SymbolChoice(symbol: "phone.fill", color: .green)),
        (["mom", "mum", "dad", "family", "friend", "maman", "papa", "famille", "ami", "عائلة", "أمي", "ابي", "صديق"], SymbolChoice(symbol: "person.2.fill", color: .pink)),
        (["dog", "cat", "chien", "chat", "كلب", "قطة", "قط"], SymbolChoice(symbol: "pawprint.fill", color: .brown)),
        (["birthday", "anniversaire", "gift", "cadeau", "عيد ميلاد", "هدية"], SymbolChoice(symbol: "gift.fill", color: .pink)),
        (["music", "guitar", "piano", "musique", "موسيقى"], SymbolChoice(symbol: "music.note", color: .pink)),
        (["game", "jeu", "لعب", "العاب"], SymbolChoice(symbol: "gamecontroller.fill", color: .purple)),
        (["train", "bus", "metro", "commute", "transport", "navigo", "مواصلات", "قطار"], SymbolChoice(symbol: "tram.fill", color: .blue)),
        (["flight", "travel", "voyage", "avion", "سفر", "طيران"], SymbolChoice(symbol: "airplane", color: .blue)),
        (["loan", "bank", "credit", "pret", "banque", "قرض", "بنك", "مصرف"], SymbolChoice(symbol: "building.columns.fill", color: .gray)),
        (["tax", "impot", "ضريبة", "ضرائب"], SymbolChoice(symbol: "building.columns.fill", color: .gray)),
        (["saving", "epargne", "ادخار", "توفير"], SymbolChoice(symbol: "banknote.fill", color: .green)),
        (["bill", "invoice", "facture", "فاتورة"], SymbolChoice(symbol: "doc.text.fill", color: .blue)),
        (["pay", "payment", "paiement", "payer", "دفع", "سداد"], SymbolChoice(symbol: "creditcard.fill", color: .green)),
        (["work", "travail", "boulot", "عمل", "شغل"], SymbolChoice(symbol: "briefcase.fill", color: .brown)),
        (["skin", "skincare", "creme", "بشرة"], SymbolChoice(symbol: "sparkles", color: .pink)),
    ]

    static func suggest(for title: String) -> SymbolChoice? {
        let text = " " + title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased() + " "
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return nil }
        for rule in rules where rule.words.contains(where: { text.contains($0) }) {
            return rule.choice
        }
        return nil
    }
}

/// Ready-made starting points shown when the app is empty and in the add menu.
enum Templates {
    struct Template: Identifiable {
        var id: String
        var title: String
        var subtitle: String
        var item: Item
    }

    static func all(today: Day = Day.today) -> [Template] {
        func make(_ id: String, _ title: String, _ subtitle: String, _ build: (inout Item) -> Void) -> Template {
            var item = Item()
            item.title = title
            if let choice = Symbols.suggest(for: title) {
                item.symbol = choice.symbol
                item.color = choice.color
            }
            item.schedule.start = today
            build(&item)
            item.schedule = item.schedule.normalized()
            return Template(id: id, title: title, subtitle: subtitle, item: item)
        }
        return [
            make("water", String(localized: "Drink water"), String(localized: "Every 2 hours after you wake up")) {
                $0.symbol = "drop.fill"; $0.color = .cyan
                $0.schedule.kind = .repeating; $0.schedule.unit = .hour; $0.schedule.every = 2
                $0.schedule.afterWaking = 0
            },
            make("meds", String(localized: "Take medication"), String(localized: "Every day at \(Format.time(8 * 60))")) {
                $0.symbol = "pills.fill"; $0.color = .red
                $0.schedule.unit = .day; $0.schedule.times = [8 * 60]
            },
            make("bed", String(localized: "Make the bed"), String(localized: "10 minutes after you wake up")) {
                $0.symbol = "bed.double.fill"; $0.color = .teal
                $0.schedule.unit = .day; $0.schedule.afterWaking = 10
            },
            make("rent", String(localized: "Rent"), String(localized: "Monthly bill on the 1st")) {
                $0.symbol = "house.fill"; $0.color = .orange
                $0.schedule.unit = .month; $0.schedule.start = today.adding(months: 1).firstOfMonth
                $0.reminder = .dayBefore
            },
            make("streaming", String(localized: "Streaming subscription"), String(localized: "Monthly, paid automatically")) {
                $0.symbol = "play.rectangle.fill"; $0.color = .red
                $0.schedule.unit = .month; $0.autopay = true; $0.reminder = .off
            },
            make("haircut", String(localized: "Haircut"), String(localized: "4 weeks after the last one")) {
                $0.symbol = "scissors"; $0.color = .purple
                $0.schedule.kind = .afterDone; $0.schedule.unit = .week; $0.schedule.every = 4
                $0.schedule.nextDue = today.adding(days: 28)
            },
            make("workout", String(localized: "Work out"), String(localized: "3 times a week, any day")) {
                $0.symbol = "dumbbell.fill"; $0.color = .orange
                $0.schedule.kind = .goal; $0.schedule.goalCount = 3; $0.schedule.goalPeriod = .week
                $0.schedule.times = [18 * 60]; $0.reminder = .whenBehind
            },
            make("trash", String(localized: "Take out the trash"), String(localized: "Every week at \(Format.time(20 * 60))")) {
                $0.symbol = "trash.fill"; $0.color = .gray
                $0.schedule.unit = .week; $0.schedule.weekdays = [today.weekday]; $0.schedule.times = [20 * 60]
            },
        ]
    }
}

extension Templates.Template {
    /// Rent and subscriptions open as bills, so they ask for an amount.
    var isBill: Bool { id == "rent" || id == "streaming" }
}
