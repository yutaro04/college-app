import Foundation

/// Web 版 `src/lib/collegeInfo.ts` の移植。「各種情報」タブの折りたたみセクション。
struct InfoSection: Identifiable, Hashable {
    let title: String
    let body: String
    var id: String { title }
}

enum CollegeInfo {
    static let sections: [InfoSection] = [
        InfoSection(
            title: "カレッジ生連絡フォーム",
            body: "https://docs.google.com/forms/d/1j1m_O74IpaC4DOoYrS0UvI7dQiEtLP4F_Jmx01Ubirc/edit"
        ),
        InfoSection(
            title: "館内規則",
            body: "https://docs.google.com/document/d/1ms8p6A0ero9kjnqjnEtEYZE759QDwuxfq9YIISnScnU/edit"
        ),
        InfoSection(
            title: "ルールブック",
            body: "https://docs.google.com/document/d/1HgVhIJGxx49mxCviEOlEoRukZqAIiuY4fzIv1IB_XKU/edit#"
        ),
        InfoSection(
            title: "リラ食ルール",
            body: "https://shimokitacollege-hlab.slack.com/archives/C02EJ0M0V8A/p1679738400659419"
        ),
        InfoSection(
            title: "メーリス",
            body: "【カレッジコミュニティ】\nカレッジ生：scholars@hlab.college\nチューター：tutors‐shimokita@hlab.college\nコーディネーター：coordinators‐shimokita@hlab.college\nHLABスタッフ：staff@h-lab.co\n【ハウス】\nハウスA：house-a-shimokita@hlab.college\nハウスB：house-b-shimokita@hlab.college\nハウスC：house-c-shimokita@hlab.college\nハウスD：house-d-shimokita@hlab.college\nハウスE：house-e-shimokita@hlab.college\nハウスF：house-f-shimokita@hlab.college\nハウスG：house-g-shimokita@hlab.college\n【カレッジ委員会】\nCIC：incubator-capital-shimokita@hlab.college\nシモキタ連携：shimokita-collab-shimokita@hlab.college\nシーズンイベント：event-shimokita@hlab.college\nアラムナイマネジメント：alumni‐management-shimokita@hlab.college\nウェルカム：welcome-shimokita@hlab.college\n図書：books-shimokita@hlab.college\nタレント省：talent-shimokita@hlab.college\nArchive?：archive-shimokita@hlab.college"
        ),
        InfoSection(
            title: "自己紹介スライド",
            body: "https://docs.google.com/presentation/d/1Ibl5ZwoUkOAzMt1nCmnU46-MW_e9dbDzqAeexnPESPk/edit#slide=id.g11a7d7828fd_1_7"
        ),
        InfoSection(
            title: "マスターシート",
            body: "https://docs.google.com/spreadsheets/d/10I6LhOohyWrTRuKtERP3u05DdzZMJvNN4MZ3qgCci0E/edit#gid=587947593"
        ),
        InfoSection(
            title: "デフォルトチャンネル",
            body: "#000_必読_staff_事務連絡\n#001_必読_staff_学事暦\n#002_必読_staff_要対応\n#010_uds_その他関係者等_事務連絡\n#011_relax食堂からのお知らせ\n#100_scholars_事務連絡\n#101_scholars_イベント告知\n#102_scholars_要対応\n#110_自己紹介の部屋\n#130_ask_anything\n#131_ask_facility\n#132_ask_parking\n#133_ask_visitors\n#134_ask_内見\n#135_ask_lock-out\n#136_ask_lost-and-found\n#137_ask_buy-and-sell\n#138_ask_この指とまれ\n#139_ask_finance\n#140_共用部-自習室_大人数利用\n#600_whatsup-college\n#601_photo-album\n#602_shimokita-info\n#603_free-food-on-campus"
        ),
        InfoSection(
            title: "経費精算",
            body: "【経費精算の方法だよ】\n①経費精算フォームを記入(レシート提出を忘れずに!)\n②翌月の15日ころに返金\nわからないことがあったらask_financeチャンネルで聞いてね。\n立て替えてくれてありがとう！\n▼経費精算フォーム▼\nhttps://docs.google.com/forms/d/e/1FAIpQLSe6Q71CALzQyTF071ZW5mr6lymfqhxSXz-s2xl9mDROzsggeA/viewform"
        ),
        InfoSection(
            title: "プリンター",
            body: "【プリンター詳細】\nプリンター：EPSON EP-M476T Series\n有線接続のみ\nマニュアルはこちら\nhttps://www2.epson.jp/support/manual/NPD7289_00_UG_JA.PDF?_gl=1*1mbb94h*_gcl_au*MjE1MDA0NTY3LjE3NDc4ODM1NTY.&_fsi=UCVbAGFx"
        ),
        InfoSection(
            title: "カンペ",
            body: "【カレッジ全体】\nプロジェクトは三社協働（下北沢の再開発プロジェクトのひとつです）小田急電鉄・UDS・HLAB\n【学食】\n平日2回（朝夜） × 5日。リラックス食堂はUDSが運営。Node Growth 湘南台でも提供（好評）。カレッジ内のみ提供（カレッジ生の友人の提供可能性あり）\n【1階構造】\n出入口が2カ所しかなく、必ず共用部を通らないとならない。その際に言葉を交わすことを意図した設計。机や椅子は動かせる。食事時間以外は自習や勉強会に向いた構造\n【2階パブリックスペース】\nリビングとしてリラックスできるように。 机は食事も勉強もできる大きさとしてオーダーメイドで作った。スクリーンが二箇所あり、ワークショップなどできる\n【HLABオフィス】\nいつでも様子が伝わるようにガラス張りのオフィス。本社をSHIMOKITA COLLEGEに。\n【キッチン】\n 料理の間に交流できるようにカウンター形式。家電はUDSチョイス。家電・食器は共用。\n【3階共有部】\n階段・エレベーターの前に共有部を配置する。調味料を共有したり工夫しながら生活をしている。\n【3階ライブラリ】\nスリッパを脱いであげる。リラックスして読書したり話す場所として設計。本はカレッジ生の持ち込みのほか、図書委員会が、毎月テーマをもって選書し、ブックイベントを行っている。\n【3階モデルルーム】\n10平米、6畳ないくらいの広さ。 家具は備え付き。ベランダには出られない。高校生は2人部屋\n【4階ランドリー】\nランドリーは男女別13個ずつ。ランドリーはこの階しかないので、全員が通る。そこでリビングでゆっくりしている人と会話することを意図。暖炉は、「寮に欠かせないもの」としてHLABがオーダーしてつけてもらった。現在は、演奏をする学生が多く、演奏スペースともなっている。\n【5階キッチン・テラス】\n5階のキッチンも誰でも使える。テラスは周りに建物が少ないこともあり、見通しよし。菜園は、カレッジ委員会の菜園部で運営をおこなっている。今後は近隣の方も招いたBBQなどをできたらいいなと考えている。"
        ),
        InfoSection(
            title: "カレッジ住所",
            body: "SHIMOKITA COLLEGE〒155-0033\n東京都世田谷区代田五丁目20番16号（各自ポスト番号）\nhttps://goo.gl/maps/3yPVq5CYg4ec6ZMr8"
        ),
        InfoSection(
            title: "wifi",
            body: "【Wi-Fi詳細】\n<共有部>\nSSID：MansionWiFi\npassword：10366202\n<自習室>\nSSID：aterm-41ea23-g,aterm-41ea23-a\npassword：319795a962c83"
        ),
        InfoSection(
            title: "ユーザーグループ",
            body: "【カレッジコミュニティ】\nscholars_メンション使用不可：カレッジ生\ntutors：チューター\nnomad-tutors：ノマドチューター\ncoordinators：コーディネーター\nchiki-coordinators：地域コーディネーター\nstaff_対応時間平日10-19時：HLABスタッフ\nalumni：アラムナイ\n【ハウス】\nhouse-leaders：ハウスリーダーズ\nhouse-a：ハウスA\nhouse-b：ハウスB\nhouse-c：ハウスC\nhouse-d：ハウスD\nhouse-e：ハウスE\nhouse-f：ハウスF\nhouse-g：ハウスG\n【カレッジ委員会】\nexecutive：委員長\ncapital：CIC\nshimokita-collab：シモキタ連携\nevent：シーズンイベント\nwelcome：ウェルカム\nsports-fes：体育祭\ncommunity-design：コミュニティデザイン\nalumni‐management：アラムナイマネジメント\nbooks：図書\ntalent：タレント省\nArchive：Archive?\nDIYer：特定の委員会にサインアップしない人々"
        ),
        InfoSection(
            title: "カラーコード",
            body: "SHIMOKITA COLLEGE\n黒：#000000\n赤：#E43D3D\n- 特色：Pantone Solid coated 179C\n青：#0033A1\n- 特色：Pantone Solid coated 286\n緑：#1C8E5D\n- 特色：Pantone Solid coated>\nHLAB COLLEGE PROGRAM\nmain：#6e1526\nsub1：#9e7d6b\nsub2：#bfcfd1\nsub3：#458c52"
        ),
        InfoSection(
            title: "バリュー",
            body: "HLAB Values\n1. とにかく学びに変えよう / Turn Everything Into Learning\n2. 実験しよう / Experiment\n3. 越境しよう / Go Beyond Borders\n4. 経験をもちよろう / Gather Experience\n5. 思いやろう / Be Compassionate"
        ),
        InfoSection(
            title: "ミッション",
            body: "カレッジのミッション｜Mission\nわたしたちは、世界に違いをもたらすリーダーを育てる、学び合いのコミュニティです。\nWe are a community of learning, nurturing leaders who make a difference in the world\n大切にする力と目指す人物像｜Educational Goals\n1. 多様性の中での共創力 ｜Co-creativity in Diversity\n身近な違いを尊重し、自身の学びと成長に変え、チームの力に昇華することができるリーダーとなる。\nBecome leaders who can respect diversity and turn differences amongst peers into self-awareness, personal growth, and team outcome\n2. 楽しみ学びを続ける姿勢｜Continued Enjoyment in Learning\n分野を跨いだ知的好奇心と情熱を持ち、一生学び続けるリーダーとなる。\nBecome leaders who strive to learn with curiosity and passion across various disciplines\n3. パブリック・マインド / 公共の精神｜Public Mind\n自分の領分を越えた関心を持ち、世のため人のために行動し続ける、変革的リーダーとなる。\nBecome transformative leaders who drive actions with a strong sense of purpose"
        ),
        InfoSection(
            title: "正式名称",
            body: "プロジェクト\nNODE CAMPUS PROJECT（ノード・キャンパス・プロジェクト）\n建物＝カレッジ\nSHIMOKITA COLLEGE（シモキタカレッジ）\nプログラム\nHLAB COLLEGE PROGRAM（HLABカレッジプログラム）\n大学生対象：Residential Program（レジデンシャル プログラム）\n高校生対象：Boarding Program（ボーディング プログラム）\n社会人対象：Tutor  Program（チューター プログラム）"
        ),
        InfoSection(
            title: "ウェルパ",
            body: "Welcome Package\nhttps://docs.google.com/document/d/1WFYD202NAb4c2uF4tTR_TcTbQKw7FGPFaStwICoDiL0/edit#heading=h.sk1egaphdrrp"
        ),
        InfoSection(
            title: "Googleカレンダー",
            body: "●001_カレッジイベント\nhttps://calendar.google.com/calendar/u/0?cid=Y19qZGNoaTEyN2IxZjhxY2tmcWw5bmo1MzZpY0Bncm91cC5jYWxlbmRhci5nb29nbGUuY29t\n●002_カレッジ委員会会議/ハウスイベント\nhttps://calendar.google.com/calendar/u/0?cid=Y18wbHFydGRuOXI1bW5tdDgxcm82MmJmMnMwZ0Bncm91cC5jYWxlbmRhci5nb29nbGUuY29t\n●003_事務連絡\nhttps://calendar.google.com/calendar/u/0?cid=Y19jZW0yZmo3b2tuamFuaGxodWhuNGRwb3V0NEBncm91cC5jYWxlbmRhci5nb29nbGUuY29t"
        ),
        InfoSection(
            title: "ポータルサイト",
            body: "https://sites.google.com/h-lab.co/hlabcollege?usp=sharing"
        ),
    ]
}
