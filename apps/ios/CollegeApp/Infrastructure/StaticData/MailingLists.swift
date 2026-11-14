import Foundation

/// Web 版 `src/lib/mailingLists.ts` の移植。イベント招待の予測変換に使う。
struct MailingList: Identifiable, Hashable {
    let category: String
    let label: String
    let email: String
    var id: String { email }
}

enum MailingLists {
    static let all: [MailingList] = [
        MailingList(category: "カレッジコミュニティ", label: "カレッジ生", email: "scholars@hlab.college"),
        MailingList(category: "カレッジコミュニティ", label: "チューター", email: "tutors‐shimokita@hlab.college"),
        MailingList(category: "カレッジコミュニティ", label: "コーディネーター", email: "coordinators‐shimokita@hlab.college"),
        MailingList(category: "カレッジコミュニティ", label: "HLABスタッフ", email: "staff@h-lab.co"),
        MailingList(category: "ハウス", label: "ハウスA", email: "house-a-shimokita@hlab.college"),
        MailingList(category: "ハウス", label: "ハウスB", email: "house-b-shimokita@hlab.college"),
        MailingList(category: "ハウス", label: "ハウスC", email: "house-c-shimokita@hlab.college"),
        MailingList(category: "ハウス", label: "ハウスD", email: "house-d-shimokita@hlab.college"),
        MailingList(category: "ハウス", label: "ハウスE", email: "house-e-shimokita@hlab.college"),
        MailingList(category: "ハウス", label: "ハウスF", email: "house-f-shimokita@hlab.college"),
        MailingList(category: "ハウス", label: "ハウスG", email: "house-g-shimokita@hlab.college"),
        MailingList(category: "カレッジ委員会", label: "CIC", email: "incubator-capital-shimokita@hlab.college"),
        MailingList(category: "カレッジ委員会", label: "シモキタ連携", email: "shimokita-collab-shimokita@hlab.college"),
        MailingList(category: "カレッジ委員会", label: "シーズンイベント", email: "event-shimokita@hlab.college"),
        MailingList(category: "カレッジ委員会", label: "アラムナイマネジメント", email: "alumni‐management-shimokita@hlab.college"),
        MailingList(category: "カレッジ委員会", label: "ウェルカム", email: "welcome-shimokita@hlab.college"),
        MailingList(category: "カレッジ委員会", label: "図書", email: "books-shimokita@hlab.college"),
        MailingList(category: "カレッジ委員会", label: "タレント省", email: "talent-shimokita@hlab.college"),
        MailingList(category: "カレッジ委員会", label: "Archive?", email: "archive-shimokita@hlab.college"),
    ]
}
