import Foundation

/// モックモードの初期データ。人物・会社名はすべて架空。
enum MockSeed {
    static let myId = "res_me"
    static let myEmail = "taro.shimokita@hlab.college"

    /// 自動ログインに使うダミーセッション
    static var session: SupabaseSession {
        SupabaseSession(
            accessToken: "mock-access-token",
            refreshToken: "mock-refresh-token",
            expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 365),
            user: SupabaseUser(id: myId, email: myEmail)
        )
    }

    // MARK: - 図鑑

    /// `0001_init.sql` の初期データと同じ
    static let categories: [AttributeCategory] = [
        .init(id: "cat_hobby", key: "hobby", label: "趣味", sortOrder: 1),
        .init(id: "cat_interest", key: "interest", label: "興味", sortOrder: 2),
        .init(id: "cat_specialty", key: "specialty", label: "専門分野", sortOrder: 3),
        .init(id: "cat_university", key: "university", label: "大学", sortOrder: 4),
        .init(id: "cat_company", key: "company", label: "会社", sortOrder: 5),
    ]

    struct ResidentSeed {
        let id: String
        let name: String
        let email: String
        let bio: String
        /// (categoryKey, value)
        let attributes: [(String, String)]
    }

    static let residents: [ResidentSeed] = [
        .init(
            id: myId, name: "下北 太郎", email: myEmail,
            bio: "アプリ開発担当です。朝のコーヒーと週末のボルダリングが日課。気軽に話しかけてください！",
            attributes: [
                ("university", "早稲田大学"), ("specialty", "ソフトウェア開発"),
                ("hobby", "コーヒー"), ("hobby", "写真"), ("hobby", "ボルダリング"), ("interest", "スタートアップ"),
            ]
        ),
        .init(
            id: "res_001", name: "佐藤 美咲", email: "misaki.sato@hlab.college",
            bio: "人がどう判断するのかを研究しています。フィルムカメラで下北の街を撮るのが好き。",
            attributes: [
                ("university", "東京大学"), ("specialty", "認知科学"),
                ("hobby", "写真"), ("hobby", "コーヒー"), ("interest", "スタートアップ"),
            ]
        ),
        .init(
            id: "res_002", name: "鈴木 健太", email: "kenta.suzuki@hlab.college",
            bio: "機械学習の研究をしつつ、いつか起業したい。ジムよりボルダリング派。",
            attributes: [
                ("university", "早稲田大学"), ("specialty", "機械学習"),
                ("hobby", "ボルダリング"), ("hobby", "コーヒー"), ("interest", "スタートアップ"),
            ]
        ),
        .init(
            id: "res_003", name: "高橋 さくら", email: "sakura.takahashi@hlab.college",
            bio: "映像を作っています。カレッジのイベント動画も撮らせてください！古着屋巡りも好きです。",
            attributes: [
                ("university", "東京藝術大学"), ("specialty", "映像制作"),
                ("hobby", "写真"), ("hobby", "古着"), ("interest", "演劇"),
            ]
        ),
        .init(
            id: "res_004", name: "田中 大輔", email: "daisuke.tanaka@hlab.college",
            bio: "社会人入居者です。PMとして働いています。キャリアの相談などなんでもどうぞ。",
            attributes: [
                ("company", "株式会社シモキタラボ"), ("specialty", "プロダクトマネジメント"),
                ("hobby", "ランニング"), ("hobby", "料理"), ("interest", "スタートアップ"),
            ]
        ),
        .init(
            id: "res_005", name: "伊藤 葵", email: "aoi.ito@hlab.college",
            bio: "地域経済のゼミに所属。共用キッチンでよく料理しているので一緒に作りましょう。",
            attributes: [
                ("university", "慶應義塾大学"), ("specialty", "経済学"),
                ("hobby", "ヨガ"), ("hobby", "料理"), ("interest", "地域活性化"),
            ]
        ),
        .init(
            id: "res_006", name: "渡辺 翔", email: "sho.watanabe@hlab.college",
            bio: "ロボットを作っています。ボードゲーム会を不定期で開催中。",
            attributes: [
                ("university", "東京科学大学"), ("specialty", "ロボティクス"),
                ("hobby", "ボードゲーム"), ("interest", "宇宙"),
            ]
        ),
        .init(
            id: "res_007", name: "山本 ひなた", email: "hinata.yamamoto@hlab.college",
            bio: "ブランドづくりに興味があります。おすすめのカフェ教えてください。",
            attributes: [
                ("university", "一橋大学"), ("specialty", "マーケティング"),
                ("hobby", "カフェ巡り"), ("hobby", "古着"), ("interest", "ファッション"),
            ]
        ),
        .init(
            id: "res_008", name: "中村 蓮", email: "ren.nakamura@hlab.college",
            bio: "フリーランスでUIデザインをしています。曲も作ります。",
            attributes: [
                ("company", "フリーランス"), ("specialty", "UIデザイン"),
                ("hobby", "写真"), ("hobby", "音楽制作"), ("interest", "演劇"),
            ]
        ),
        .init(
            id: "res_009", name: "小林 結衣", email: "yui.kobayashi@hlab.college",
            bio: "公衆衛生を勉強中。朝ランの仲間を募集しています。",
            attributes: [
                ("university", "東京大学"), ("specialty", "公衆衛生"),
                ("hobby", "ランニング"), ("interest", "国際協力"),
            ]
        ),
        .init(
            id: "res_010", name: "加藤 悠真", email: "yuma.kato@hlab.college",
            bio: "近所のブルワリーで働いています。発酵の話ならいくらでもできます。",
            attributes: [
                ("company", "シモキタブルワリー"), ("specialty", "発酵"),
                ("hobby", "クラフトビール"), ("hobby", "料理"), ("interest", "地域活性化"),
            ]
        ),
        .init(
            id: "res_011", name: "吉田 陽菜", email: "hina.yoshida@hlab.college",
            bio: "建築を学んでいます。銭湯とまちの古い建物が好き。",
            attributes: [
                ("university", "早稲田大学"), ("specialty", "建築"),
                ("hobby", "銭湯巡り"), ("hobby", "カフェ巡り"), ("interest", "まちづくり"),
            ]
        ),
        .init(
            id: "res_012", name: "Alex Kim", email: "alex.kim@hlab.college",
            bio: "Exchange student from Seoul. 日本語勉強中です！Let's talk in English or Japanese.",
            attributes: [
                ("university", "慶應義塾大学"), ("specialty", "国際関係"),
                ("hobby", "ボルダリング"), ("hobby", "コーヒー"), ("interest", "国際協力"),
            ]
        ),
    ]

    // MARK: - コーヒーチャット

    struct CoffeeChatSeed {
        let id: String
        let from: String
        let to: String
        let status: CoffeeChatRequest.Status
        let message: String?
        let minutesAgo: Int
    }

    static let coffeeChats: [CoffeeChatSeed] = [
        .init(id: "req_001", from: "res_001", to: myId, status: .pending,
              message: "写真の話を聞きたいです！今週どこかでお茶しませんか？", minutesAgo: 120),
        .init(id: "req_002", from: "res_004", to: myId, status: .pending,
              message: "スタートアップ界隈の話、ぜひしましょう", minutesAgo: 60 * 26),
        .init(id: "req_003", from: myId, to: "res_002", status: .pending,
              message: "機械学習の研究の話を聞かせてください！", minutesAgo: 300),
        .init(id: "req_004", from: myId, to: "res_003", status: .accepted,
              message: "イベント動画の撮り方を教えてほしいです", minutesAgo: 60 * 72),
        .init(id: "req_005", from: "res_006", to: myId, status: .declined,
              message: nil, minutesAgo: 60 * 120),
    ]

    // MARK: - 交流機能（店名・ペンネームなどはすべて架空）

    static let penNames = [
        "夜更かしのフクロウ", "春の風見鶏", "迷子の灯台", "ひなたぼっこ", "雨上がりの猫",
        "真夜中のパン屋", "旅するペンギン", "静かな本棚", "月見団子", "青いポスト",
    ]

    static let penPalReplies = [
        "お手紙ありがとう！読んでいてほっこりしました。最近は寒くなってきたので、温かい飲み物が手放せません。",
        "返事が遅くなってごめんなさい。実は同じことを考えていました。今度はあなたのおすすめも教えてください。",
        "とても素敵な話ですね。わたしは最近、屋上で夕焼けを見るのが日課です。",
        "なるほど…！その考え方、真似してみます。ところで最近読んだ本はありますか？",
    ]

    static func social(now: Date) -> MockSocialState {
        var state = MockSocialState()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: .minute, value: dayOffset * 24 * 60 + hour * 60 + minute, to: today)!
        }

        state.recommendations = [
            ("res_001", "喫茶ミモザ", Recommendation.Genre.cafe, "下北沢 南口", "固めのプリンと深煎りコーヒー。窓際の席は写真映えします", 30),
            ("res_002", "Roast Lab 北沢", .cafe, "下北沢 北口", "浅煎りのハンドドリップが絶品。電源あり・作業しやすい", 120),
            ("res_004", "定食こむぎ", .restaurant, "東北沢", "日替わり定食が900円で量が多い。平日の昼におすすめ", 300),
            ("res_005", "スパイスロード", .restaurant, "下北沢", "3種あいがけカレー。辛さを選べるので辛いのが苦手でも大丈夫", 600),
            ("res_010", "ビアスタンド発酵所", .bar, "世田谷代田", "クラフトビールが常時10種類。発酵食品のおつまみも", 900),
            ("res_003", "古着屋ひとつめ", .shop, "下北沢", "70年代の古着が多め。店主さんが優しくて話しやすい", 1500),
            ("res_007", "Café Lumière", .cafe, "池ノ上", "静かで読書向き。チーズケーキが好き", 2000),
            ("res_011", "代田の湯", .other, "世田谷代田", "昔ながらの銭湯。タイル絵がきれいで建築好きにも", 2600),
            ("res_me", "珈琲ほとり", .cafe, "下北沢", "朝8時から開いてる。モーニングのトーストがおすすめ", 3000),
            ("res_008", "レコード屋ノイズ", .shop, "下北沢", "インディーズの品揃えがすごい。試聴もできる", 4000),
        ].enumerated().map { index, r in
            .init(id: "rec_\(index + 1)", residentId: r.0, name: r.1, genre: r.2, area: r.3, comment: r.4,
                  url: nil, createdAt: iso(minutesAgo: r.5))
        }

        state.likes = [
            .init(from: "res_001", to: myId, kind: "like", topic: "コーヒー", createdAt: iso(minutesAgo: 600)),
            .init(from: myId, to: "res_001", kind: "like", topic: "写真", createdAt: iso(minutesAgo: 300)),
            .init(from: "res_002", to: myId, kind: "like", topic: "ボルダリング", createdAt: iso(minutesAgo: 200)),
            .init(from: "res_008", to: myId, kind: "like", topic: "写真", createdAt: iso(minutesAgo: 100)),
            .init(from: myId, to: "res_006", kind: "pass", topic: nil, createdAt: iso(minutesAgo: 1000)),
        ]

        state.wishes = [
            ("res_011", "銭湯行くなら誘って", "平日の夜ならだいたいOK", 60),
            ("res_006", "ボドゲやるなら誘って", "重ゲーも歓迎です", 180),
            ("res_009", "朝ランするなら誘って", nil, 400),
            ("res_012", "英語で話したい人いたら誘って", "Language exchange 大歓迎！", 700),
            ("res_003", "撮影のモデル探してたら誘って", nil, 1200),
            ("res_010", "飲みに行くなら誘って", "ビールならなんでも", 1600),
            (myId, "ボルダリング行くなら誘って", "週末なら行けます", 2000),
            ("res_005", "料理会やるなら誘って", nil, 2500),
        ].enumerated().map { index, w in
            .init(id: "wish_\(index + 1)", residentId: w.0, title: w.1, note: w.2, createdAt: iso(minutesAgo: w.3))
        }
        state.wishInvitations = [
            .init(id: "winv_1", wishId: "wish_7", inviterId: "res_002",
                  message: "今週の土曜、北沢のジム行きませんか？", createdAt: iso(minutesAgo: 90)),
        ]

        // 空き時間: 人ごとに少しずつずらして 1 週間分作る
        let hours = [10, 13, 15, 18, 19, 20]
        for (i, resident) in residents.enumerated() {
            for day in 0..<7 where (i + day) % 3 != 0 {
                let start = at(day, hours[(i * 2 + day) % hours.count])
                let end = start.addingTimeInterval(TimeInterval((2 + (i + day) % 2) * 3600))
                guard end > now else { continue }
                state.slots.append(.init(id: "slot_\(resident.id)_\(day)", residentId: resident.id,
                                         start: start, end: end, note: nil))
            }
        }

        let nextHour = cal.date(bySetting: .minute, value: 0, of: now.addingTimeInterval(3600)) ?? now
        state.gatherings = [
            .init(id: "gath_1", hostId: "res_006", title: "ボドゲやる人〜", location: "ラウンジ",
                  start: nextHour, end: nextHour.addingTimeInterval(3 * 3600), capacity: 5,
                  note: "初心者向けの軽いゲームから始めます", participantIds: ["res_002", "res_012"]),
            .init(id: "gath_2", hostId: "res_005", title: "共用キッチンで餃子パーティー", location: "共用キッチン",
                  start: at(1, 18, 30), end: at(1, 21), capacity: 6,
                  note: "材料費 300 円くらい", participantIds: ["res_010", "res_004", "res_009"]),
            .init(id: "gath_3", hostId: "res_009", title: "朝ラン 5km", location: "1F エントランス",
                  start: at(2, 6, 30), end: at(2, 7, 30), capacity: nil, note: nil, participantIds: []),
        ]

        state.threads = [
            .init(id: "pp_1", starterId: myId, partnerId: "res_007", starterAlias: "夜更かしのフクロウ",
                  partnerAlias: "春の風見鶏", createdAt: iso(minutesAgo: 60 * 48)),
            .init(id: "pp_2", starterId: "res_009", partnerId: myId, starterAlias: "ひなたぼっこ",
                  partnerAlias: "迷子の灯台", createdAt: iso(minutesAgo: 180)),
        ]
        state.letters = [
            .init(id: "ltr_1", threadId: "pp_1", senderId: myId,
                  body: "はじめまして。カレッジに住んでいる誰かさんへ。最近ハマっていることはありますか？",
                  createdAt: iso(minutesAgo: 60 * 48), readAt: iso(minutesAgo: 60 * 30)),
            .init(id: "ltr_2", threadId: "pp_1", senderId: "res_007",
                  body: "はじめまして！最近は朝の散歩にハマっています。下北の朝は静かで好きです。あなたは？",
                  createdAt: iso(minutesAgo: 60 * 24), readAt: iso(minutesAgo: 60 * 20)),
            .init(id: "ltr_3", threadId: "pp_2", senderId: "res_009",
                  body: "突然のお手紙すみません。最近ちょっと疲れ気味で…元気が出ることって何かありますか？",
                  createdAt: iso(minutesAgo: 180), readAt: nil),
        ]
        return state
    }

    // MARK: - ひま（Supabase テーブル）

    static let himaInviters: [(id: String, message: String)] = [
        ("res_011", "銭湯行きません？"),
        ("res_005", "一緒に夕飯作りましょう〜"),
        ("res_002", "ラウンジでコーヒー飲もう"),
    ]

    static func tables() -> [String: [[String: Any]]] {
        [
            "availability": [
                availability("res_002", "ラウンジでコーヒー飲んでます", minutesAgo: 10, expiresInMinutes: 120),
                availability("res_005", "夕飯一緒に作る人〜", minutesAgo: 30, expiresInMinutes: 180),
                availability("res_010", "屋上で一杯どうですか", minutesAgo: 5, expiresInMinutes: 60),
            ],
            "availability_invites": [],
            "invite_groups": [
                ["id": "grp_001", "name": "3F のみんな", "emails": ["misaki.sato@hlab.college", "kenta.suzuki@hlab.college"],
                 "created_at": iso(minutesAgo: 60 * 24 * 10)],
            ],
            "created_events": [],
        ]
    }

    private static func availability(_ userId: String, _ message: String, minutesAgo: Int, expiresInMinutes: Int) -> [String: Any] {
        [
            "id": "avail_\(userId)",
            "user_id": userId,
            "message": message,
            "expires_at": ISODate.string(from: Date().addingTimeInterval(TimeInterval(expiresInMinutes * 60))),
            "created_at": iso(minutesAgo: minutesAgo),
        ]
    }

    // MARK: - カレンダー（Web 版 Next.js API）

    static let postConfig: [String: Any] = [
        "calendars": [
            ["key": "event", "name": "000_イベントカレンダー"],
            ["key": "house", "name": "001_ハウス/委員会"],
            ["key": "private", "name": "プライベート"],
        ],
        "rooms": [
            ["label": "ラウンジ", "email": "lounge@hlab.college"],
            ["label": "シアタールーム", "email": "theater@hlab.college"],
            ["label": "屋上", "email": "rooftop@hlab.college"],
        ],
    ]

    static func calendarName(for key: String) -> String {
        let calendars = postConfig["calendars"] as? [[String: String]] ?? []
        return calendars.first { $0["key"] == key }?["name"] ?? key
    }

    /// 今日を起点に 2 週間分のイベントを作る
    static func events() -> [CalendarEvent] {
        let specs: [(day: Int, start: String, end: String, title: String, location: String, house: Bool, color: String)] = [
            // 過去のイベント（日記タブの「イベント」でクリップを撮る対象）
            (-1, "19:00", "21:30", "鍋パーティー", "共用キッチン", false, "#F59E0B"),
            (-4, "14:00", "17:00", "下北沢 古着屋めぐり", "1F エントランス集合", false, "#10B981"),
            (-8, "18:00", "21:00", "屋上で月見会", "屋上", false, "#8B5CF6"),
            (0, "19:00", "20:30", "【全員】ハウスミーティング", "ラウンジ", true, "#CB1B3B"),
            (0, "21:00", "23:00", "映画上映会『下北沢物語』", "シアタールーム", false, "#3B82F6"),
            (1, "07:00", "08:00", "朝ヨガ", "屋上", false, "#10B981"),
            (2, "19:30", "21:00", "コーヒーチャット交流会", "ラウンジ", false, "#8B5CF6"),
            (3, "18:00", "21:00", "料理会：スパイスカレー", "共用キッチン", false, "#F59E0B"),
            (4, "20:00", "22:00", "ボードゲームナイト", "ラウンジ", false, "#3B82F6"),
            (5, "13:00", "16:00", "下北沢まち歩き", "1F エントランス集合", false, "#10B981"),
            (7, "10:00", "12:00", "【新入生】オリエンテーション", "ラウンジ", true, "#CB1B3B"),
            (8, "19:00", "20:30", "読書会", "ライブラリー", false, "#8B5CF6"),
            (10, "17:00", "20:00", "屋上BBQ", "屋上", false, "#F59E0B"),
            (12, "19:00", "21:00", "広報委員会", "会議室", true, "#64748B"),
            (13, "18:30", "20:30", "思い出ビデオ上映会", "シアタールーム", false, "#3B82F6"),
        ]
        let today = Calendar.current.startOfDay(for: Date())
        var events: [CalendarEvent] = specs.enumerated().map { index, spec in
            let date = Calendar.current.date(byAdding: .day, value: spec.day, to: today)!
            let key = DateUtil.dateKey(date)
            return CalendarEvent(
                id: "evt_\(String(format: "%03d", index + 1))",
                calendarName: spec.house ? "001_ハウス/委員会" : "000_イベントカレンダー",
                title: spec.title,
                description: "モックデータのイベントです。",
                location: spec.location,
                startISO: DateUtil.iso(dateKey: key, time: spec.start),
                endISO: DateUtil.iso(dateKey: key, time: spec.end),
                dateKey: key, startTime: spec.start, endTime: spec.end,
                displayDate: displayDate(key), isAllDay: false, color: spec.color
            )
        }
        let allDayKey = DateUtil.dateKey(Calendar.current.date(byAdding: .day, value: 6, to: today)!)
        events.append(CalendarEvent(
            id: "evt_allday", calendarName: "001_ハウス/委員会", title: "大掃除デー",
            description: "共用部の大掃除です。", location: "全館",
            startISO: DateUtil.iso(dateKey: allDayKey, time: "00:00"), endISO: DateUtil.iso(dateKey: allDayKey, time: "23:59"),
            dateKey: allDayKey, startTime: "", endTime: "", displayDate: displayDate(allDayKey),
            isAllDay: true, color: "#64748B"
        ))
        return events
    }

    // MARK: - ユーティリティ

    static func iso(minutesAgo: Int) -> String {
        ISODate.string(from: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    /// yyyy-MM-dd → M/d
    static func displayDate(_ dateKey: String) -> String {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        return "\(parts[1])/\(parts[2])"
    }

    /// ISO → HH:mm（ローカル時刻）
    static func hhmm(_ iso: String) -> String {
        guard let date = ISODate.parse(iso) else { return "" }
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
