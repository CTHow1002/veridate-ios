import Foundation

enum LocalizedProfileDisplay {
    static func gender(_ value: GenderType) -> String {
        option(value.rawValue)
    }

    static func maritalStatus(_ value: MaritalStatus) -> String {
        option(value.rawValue)
    }

    static func relationshipGoal(_ value: RelationshipIntention) -> String {
        option(value.rawValue)
    }

    static func language(_ value: String) -> String {
        if value.trimmingCharacters(in: .whitespacesAndNewlines) == "Malay" {
            return AppLanguageManager.localized("filterOption.language.malay")
        }

        return option(value)
    }

    static func languageList(_ value: String?) -> String? {
        let values = (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !values.isEmpty else { return nil }
        return values.map { language($0) }.joined(separator: ", ")
    }

    static func option(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "":
            return AppLanguageManager.localized("common_not_added")
        case "male":
            return AppLanguageManager.localized("gender.male")
        case "female":
            return AppLanguageManager.localized("gender.female")
        case "non_binary":
            return AppLanguageManager.localized("gender.nonBinary")
        case "other", "Other":
            return AppLanguageManager.localized("filterOption.common.other")
        case "opposite_gender":
            return AppLanguageManager.localized("genderInterest.oppositeGender")
        case "men":
            return AppLanguageManager.localized("genderInterest.men")
        case "women":
            return AppLanguageManager.localized("genderInterest.women")
        case "everyone":
            return AppLanguageManager.localized("genderInterest.everyone")
        case "single":
            return AppLanguageManager.localized("maritalStatus.single")
        case "divorced":
            return AppLanguageManager.localized("maritalStatus.divorced")
        case "widowed":
            return AppLanguageManager.localized("maritalStatus.widowed")
        case "separated":
            return AppLanguageManager.localized("maritalStatus.separated")
        case "prefer_not_to_say", "Prefer not to say":
            return AppLanguageManager.localized("maritalStatus.preferNotToSay")
        case "serious_relationship":
            return AppLanguageManager.localized("relationshipGoal.seriousRelationship")
        case "marriage":
            return AppLanguageManager.localized("relationshipGoal.marriage")
        case "friendship_first", "friendship":
            return AppLanguageManager.localized("relationshipGoal.friendshipFirst")
        case "not_sure", "still_figuring_out":
            return AppLanguageManager.localized("relationshipGoal.notSure")
        case "Primary school", "Primary School":
            return AppLanguageManager.localized("filterOption.education.primarySchool")
        case "High school", "High School":
            return AppLanguageManager.localized("filterOption.education.highSchool")
        case "Diploma":
            return AppLanguageManager.localized("filterOption.education.diploma")
        case "Degree":
            return AppLanguageManager.localized("filterOption.education.degree")
        case "Master":
            return AppLanguageManager.localized("filterOption.education.master")
        case "PhD":
            return AppLanguageManager.localized("filterOption.education.phd")
        case "Student":
            return AppLanguageManager.localized("filterOption.common.student")
        case "Unemployed":
            return AppLanguageManager.localized("filterOption.common.unemployed")
        case "Aries":
            return AppLanguageManager.localized("filterOption.zodiac.aries")
        case "Taurus":
            return AppLanguageManager.localized("filterOption.zodiac.taurus")
        case "Gemini":
            return AppLanguageManager.localized("filterOption.zodiac.gemini")
        case "Cancer":
            return AppLanguageManager.localized("filterOption.zodiac.cancer")
        case "Leo":
            return AppLanguageManager.localized("filterOption.zodiac.leo")
        case "Virgo":
            return AppLanguageManager.localized("filterOption.zodiac.virgo")
        case "Libra":
            return AppLanguageManager.localized("filterOption.zodiac.libra")
        case "Scorpio":
            return AppLanguageManager.localized("filterOption.zodiac.scorpio")
        case "Sagittarius":
            return AppLanguageManager.localized("filterOption.zodiac.sagittarius")
        case "Capricorn":
            return AppLanguageManager.localized("filterOption.zodiac.capricorn")
        case "Aquarius":
            return AppLanguageManager.localized("filterOption.zodiac.aquarius")
        case "Pisces":
            return AppLanguageManager.localized("filterOption.zodiac.pisces")
        case "Malay":
            return AppLanguageManager.localized("filterOption.common.malay")
        case "Chinese":
            return AppLanguageManager.localized("filterOption.race.chinese")
        case "Indian":
            return AppLanguageManager.localized("filterOption.race.indian")
        case "Iban":
            return AppLanguageManager.localized("filterOption.race.iban")
        case "Kadazan":
            return AppLanguageManager.localized("filterOption.race.kadazan")
        case "Mixed":
            return AppLanguageManager.localized("filterOption.race.mixed")
        case "Islam":
            return AppLanguageManager.localized("filterOption.religion.islam")
        case "Buddhism":
            return AppLanguageManager.localized("filterOption.religion.buddhism")
        case "Christianity":
            return AppLanguageManager.localized("filterOption.religion.christianity")
        case "Hinduism":
            return AppLanguageManager.localized("filterOption.religion.hinduism")
        case "Taoism":
            return AppLanguageManager.localized("filterOption.religion.taoism")
        case "Atheist":
            return AppLanguageManager.localized("filterOption.religion.atheist")
        case "Agnostic":
            return AppLanguageManager.localized("filterOption.religion.agnostic")
        case "Spiritual":
            return AppLanguageManager.localized("filterOption.religion.spiritual")
        case "Never":
            return AppLanguageManager.localized("filterOption.frequency.never")
        case "Socially":
            return AppLanguageManager.localized("filterOption.frequency.socially")
        case "Sometimes":
            return AppLanguageManager.localized("filterOption.frequency.sometimes")
        case "Often":
            return AppLanguageManager.localized("filterOption.frequency.often")
        case "Daily":
            return AppLanguageManager.localized("filterOption.frequency.daily")
        case "A few times a week":
            return AppLanguageManager.localized("filterOption.exercise.fewTimesAWeek")
        case "Rarely":
            return AppLanguageManager.localized("filterOption.frequency.rarely")
        case "Dog":
            return AppLanguageManager.localized("filterOption.pet.dog")
        case "Cat":
            return AppLanguageManager.localized("filterOption.pet.cat")
        case "Fish":
            return AppLanguageManager.localized("filterOption.pet.fish")
        case "Bird":
            return AppLanguageManager.localized("filterOption.pet.bird")
        case "Rabbit":
            return AppLanguageManager.localized("filterOption.pet.rabbit")
        case "Hamster":
            return AppLanguageManager.localized("filterOption.pet.hamster")
        case "Reptile":
            return AppLanguageManager.localized("filterOption.pet.reptile")
        case "Have pets":
            return AppLanguageManager.localized("filterOption.pet.havePets")
        case "Want pets":
            return AppLanguageManager.localized("filterOption.pet.wantPets")
        case "No pet but love them":
            return AppLanguageManager.localized("filterOption.pet.noPetButLoveThem")
        case "Not a pet person":
            return AppLanguageManager.localized("filterOption.pet.notPetPerson")
        case "Allergic to pets":
            return AppLanguageManager.localized("filterOption.pet.allergic")
        case "Responsive texter":
            return AppLanguageManager.localized("filterOption.communication.responsiveTexter")
        case "Thoughtful texter":
            return AppLanguageManager.localized("filterOption.communication.thoughtfulTexter")
        case "Phone calls":
            return AppLanguageManager.localized("filterOption.communication.phoneCalls")
        case "Video calls":
            return AppLanguageManager.localized("filterOption.communication.videoCalls")
        case "Voice messages":
            return AppLanguageManager.localized("filterOption.communication.voiceMessages")
        case "In-person conversations":
            return AppLanguageManager.localized("filterOption.communication.inPerson")
        case "Plans ahead":
            return AppLanguageManager.localized("filterOption.communication.plansAhead")
        case "Spontaneous check-ins":
            return AppLanguageManager.localized("filterOption.communication.spontaneousCheckIns")
        case "Low-maintenance communicator":
            return AppLanguageManager.localized("filterOption.communication.lowMaintenance")
        case "Quality time":
            return AppLanguageManager.localized("filterOption.loveLanguage.qualityTime")
        case "Words of affirmation":
            return AppLanguageManager.localized("filterOption.loveLanguage.wordsOfAffirmation")
        case "Acts of service":
            return AppLanguageManager.localized("filterOption.loveLanguage.actsOfService")
        case "Physical touch":
            return AppLanguageManager.localized("filterOption.loveLanguage.physicalTouch")
        case "Receiving gifts":
            return AppLanguageManager.localized("filterOption.loveLanguage.receivingGifts")
        case "Not sure yet":
            return AppLanguageManager.localized("filterOption.common.notSureYet")
        case "NOT SURE":
            return AppLanguageManager.localized("filterOption.mbti.notSure")
        case "Not sure":
            return AppLanguageManager.localized("filterOption.mbti.notSure")
        case "English":
            return AppLanguageManager.localized("filterOption.language.english")
        case "Mandarin":
            return AppLanguageManager.localized("filterOption.language.mandarin")
        case "Cantonese":
            return AppLanguageManager.localized("filterOption.language.cantonese")
        case "Tamil":
            return AppLanguageManager.localized("filterOption.language.tamil")
        case "Hokkien":
            return AppLanguageManager.localized("filterOption.language.hokkien")
        case "Hakka":
            return AppLanguageManager.localized("filterOption.language.hakka")
        case "Teochew":
            return AppLanguageManager.localized("filterOption.language.teochew")
        case "Japanese":
            return AppLanguageManager.localized("filterOption.language.japanese")
        case "Korean":
            return AppLanguageManager.localized("filterOption.language.korean")
        case "Arabic":
            return AppLanguageManager.localized("filterOption.language.arabic")
        case "Hindi":
            return AppLanguageManager.localized("filterOption.language.hindi")
        case "Indonesian":
            return AppLanguageManager.localized("filterOption.language.indonesian")
        case "Thai":
            return AppLanguageManager.localized("filterOption.language.thai")
        case "Want children":
            return AppLanguageManager.localized("filterOption.familyPlans.wantChildren")
        case "Open to children":
            return AppLanguageManager.localized("filterOption.familyPlans.openToChildren")
        case "Do not want children":
            return AppLanguageManager.localized("filterOption.familyPlans.doNotWantChildren")
        case "Have children":
            return AppLanguageManager.localized("filterOption.familyPlans.haveChildren")
        case "Coffee":
            return AppLanguageManager.localized("interest.coffee")
        case "Cafe Hopping":
            return AppLanguageManager.localized("interest.cafeHopping")
        case "Foodie":
            return AppLanguageManager.localized("interest.foodie")
        case "Cooking":
            return AppLanguageManager.localized("interest.cooking")
        case "Baking":
            return AppLanguageManager.localized("interest.baking")
        case "Desserts":
            return AppLanguageManager.localized("interest.desserts")
        case "Tea":
            return AppLanguageManager.localized("interest.tea")
        case "Brunch":
            return AppLanguageManager.localized("interest.brunch")
        case "Gym":
            return AppLanguageManager.localized("interest.gym")
        case "Running":
            return AppLanguageManager.localized("interest.running")
        case "Hiking":
            return AppLanguageManager.localized("interest.hiking")
        case "Yoga":
            return AppLanguageManager.localized("interest.yoga")
        case "Cycling":
            return AppLanguageManager.localized("interest.cycling")
        case "Swimming":
            return AppLanguageManager.localized("interest.swimming")
        case "Badminton":
            return AppLanguageManager.localized("interest.badminton")
        case "Football":
            return AppLanguageManager.localized("interest.football")
        case "Dancing":
            return AppLanguageManager.localized("interest.dancing")
        case "Music":
            return AppLanguageManager.localized("interest.music")
        case "Movies":
            return AppLanguageManager.localized("interest.movies")
        case "Books":
            return AppLanguageManager.localized("interest.books")
        case "Art":
            return AppLanguageManager.localized("interest.art")
        case "Photography":
            return AppLanguageManager.localized("interest.photography")
        case "Concerts":
            return AppLanguageManager.localized("interest.concerts")
        case "Museums":
            return AppLanguageManager.localized("interest.museums")
        case "Karaoke":
            return AppLanguageManager.localized("interest.karaoke")
        case "Fashion":
            return AppLanguageManager.localized("interest.fashion")
        case "Pets":
            return AppLanguageManager.localized("interest.pets")
        case "Night Owl":
            return AppLanguageManager.localized("interest.nightOwl")
        case "Early Bird":
            return AppLanguageManager.localized("interest.earlyBird")
        case "Family-Oriented":
            return AppLanguageManager.localized("interest.familyOriented")
        case "Career-Focused":
            return AppLanguageManager.localized("interest.careerFocused")
        case "Skincare":
            return AppLanguageManager.localized("interest.skincare")
        case "Spirituality":
            return AppLanguageManager.localized("interest.spirituality")
        case "Volunteering":
            return AppLanguageManager.localized("interest.volunteering")
        case "Travel":
            return AppLanguageManager.localized("interest.travel")
        case "Nature":
            return AppLanguageManager.localized("interest.nature")
        case "Beach":
            return AppLanguageManager.localized("interest.beach")
        case "Road Trips":
            return AppLanguageManager.localized("interest.roadTrips")
        case "Gaming":
            return AppLanguageManager.localized("interest.gaming")
        case "Board Games":
            return AppLanguageManager.localized("interest.boardGames")
        case "Anime":
            return AppLanguageManager.localized("interest.anime")
        case "Tech":
            return AppLanguageManager.localized("interest.tech")
        case "Finance":
            return AppLanguageManager.localized("interest.finance")
        case "A green flag I look for is...":
            return AppLanguageManager.localized("profilePrompt.greenFlag")
        case "My ideal relationship feels like...":
            return AppLanguageManager.localized("profilePrompt.idealRelationship")
        case "Sunday usually means...":
            return AppLanguageManager.localized("profilePrompt.sundayUsuallyMeans")
        case "The way to win me over is...":
            return AppLanguageManager.localized("profilePrompt.winMeOver")
        case "One thing people misunderstand about me is...":
            return AppLanguageManager.localized("profilePrompt.misunderstood")
        case "I am happiest when...":
            return AppLanguageManager.localized("profilePrompt.happiestWhen")
        case "My perfect weekend includes...":
            return AppLanguageManager.localized("profilePrompt.perfectWeekend")
        case "A small thing I appreciate is...":
            return AppLanguageManager.localized("profilePrompt.smallThingIAppreciate")
        case "I feel most connected when...":
            return AppLanguageManager.localized("profilePrompt.feelConnected")
        case "Together, I would love to...":
            return AppLanguageManager.localized("profilePrompt.togetherLoveTo")
        case "The best way to support me is...":
            return AppLanguageManager.localized("profilePrompt.supportMe")
        case "A value I live by is...":
            return AppLanguageManager.localized("profilePrompt.valueILiveBy")
        case "I will always make time for...":
            return AppLanguageManager.localized("profilePrompt.makeTimeFor")
        case "My simple joy is...":
            return AppLanguageManager.localized("profilePrompt.simpleJoy")
        case "A date I would never forget is...":
            return AppLanguageManager.localized("profilePrompt.unforgettableDate")
        case "I know I like someone when...":
            return AppLanguageManager.localized("profilePrompt.knowILikeSomeone")
        default:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func list(_ value: String?) -> String? {
        let values = (value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !values.isEmpty else { return nil }
        return values.map { option($0) }.joined(separator: ", ")
    }
}
