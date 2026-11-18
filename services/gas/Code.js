/**
 * COLLEGE APP の共有カレンダー用 GAS（Google Apps Script の Web アプリ）。
 *
 * 新 API（services/api。Cloudflare Workers）からだけ呼ばれ、スクリプトの持ち主の権限で
 * 共有カレンダー（000_イベント / 001_ハウス・委員会）と ROOM を読み書きする。
 *   GET  ?action=events&from=ISO&to=ISO&secret=…  予定の一覧（新 API の Cron が 15 分ごとに呼び、D1 に入れる）
 *   GET  ?action=config&secret=…                  投稿フォームの選択肢（カレンダー名・ROOM 一覧）
 *   POST {secret, calendarKey, title, …}           イベント作成
 *
 * 以前はスプレッドシート（EventCache）に予定を書き出していたが、新 API が D1 に溜めるので廃止した。
 *
 * 設定: Apps Script エディタの「プロジェクトの設定」→「スクリプト プロパティ」に
 *   POST_SECRET = 新 API の GAS_POST_SECRET と同じ値
 * を入れること（シークレットはコードに書かない）。
 */

const SYNC_MAX_DAYS = 120;

// フロントのカレンダー選択肢 key -> { id: カレンダーID, name: 表示名 }
// id はGoogleカレンダーの設定 >「カレンダーの統合」に表示されるカレンダーID
// （例: 'c_xxxxxxxx@group.calendar.google.com'）。両カレンダーに「予定の変更」権限が必要。
const POST_CALENDARS = {
    event: { id: 'c_jdchi127b1f8qckfql9nj536ic@group.calendar.google.com', name: '000_イベントカレンダー' },
    house: { id: 'c_0lqrtdn9r5mnmt81ro62bf2s0g@group.calendar.google.com', name: '001_ハウス/委員会' },
};

// 選択できるROOM（Googleカレンダーのリソース）。
// email は POST_CALENDARS のIDとは別物で、ROOMというリソース自体の固有アドレス
// （c_xxxx@resource.calendar.google.com 形式。listAllCalendarIds() で確認可能）。
// 予約はイベントにROOMをゲスト招待する方式なので、どちらのカレンダーに投稿しても
// 同じROOMを予約できる（投稿先カレンダーとROOMは独立した選択肢）。
// 空配列の場合、フロントのROOM選択は非表示になります。
const ROOMS = [
    // --- 1F ---
    { label: '1F ソファーエリア (6)', email: 'c_1889hv8mg3fo2g95kmv8itg21i9lg@resource.calendar.google.com' },
    { label: '1F テナントスペース (20)', email: 'c_1889v5q1odkn8imqgn3jthotn8jnm4g8d0mmoob25phmu@resource.calendar.google.com' },
    { label: '1F リラックス食堂前 (15)', email: 'c_188f74gbk8e5ohm9grl0cdplht7hk@resource.calendar.google.com' },
    { label: '1F リラ食付近テーブルエリア (6)', email: 'c_188fd6mgaj8a8g4mjdpgeiggjjse6@resource.calendar.google.com' },
    { label: '1F 中央長テーブル (12)', email: 'c_188ff36fdba1ug89k6vadh690dgvg@resource.calendar.google.com' },
    { label: '1F 正面玄関付近テーブルエリア (12)', email: 'c_188ddnfoj3aa4hmdjh9ar3mu9fq06@resource.calendar.google.com' },
    { label: '1F 自習室 (12)', email: 'c_188acu3vuhjb8grli2jkt8g10k0ts@resource.calendar.google.com' },
    { label: '1F 個室122（HLABスタッフのみ） (2)', email: 'c_1884tjefc6toeg7on37thkf1fqvdc@resource.calendar.google.com' },
    // --- 2F ---
    { label: '2F キッチン (10)', email: 'c_188cl7cd2au4ijqpmh9tt4m8o88us@resource.calendar.google.com' },
    { label: '2F キッチン前テーブル (20)', email: 'c_188bo060ckcfqgdmmrv0inpoa4sug@resource.calendar.google.com' },
    { label: '2F スクリーン前 (30)', email: 'c_188eb7n616sb2jhrhmc262muk4oou@resource.calendar.google.com' },
    { label: '2F 本棚前ソファースペース (20)', email: 'c_188bqkfs1ste0ht7k358hsk41iqbk@resource.calendar.google.com' },
    { label: '2F オフィス（HLABスタッフのみ） (20)', email: 'c_18876869uvj1mj2uhlb6ni039r8084g8d0mmoob25phmu@resource.calendar.google.com' },
    // --- 3F ---
    { label: '3F キッチン (15)', email: 'c_188am6320f3jcin8jpu5g16lhr1ji@resource.calendar.google.com' },
    { label: '3F ライブラリー (10)', email: 'c_1882hvcqdp2m2j45gen9u1a7aqm3g@resource.calendar.google.com' },
    // --- 4F・5F ---
    { label: '4F ラウンジ (15)', email: 'c_1880r30iopb0ejhhj9u47ivk1ktj4@resource.calendar.google.com' },
    { label: '5F テラス (15)', email: 'c_18871a195bh6kht5giq755qgb84ua@resource.calendar.google.com' },
    { label: '5F キッチン (15)', email: 'c_188em4cctok36glenc2nsmpc3jebo@resource.calendar.google.com' },
    // --- 設備・物品 ---
    { label: 'スクリーン（可動式）', email: 'c_188aa49ggco8aj21i5bf8koo5475s4g8d0mmoob25phmu@resource.calendar.google.com' },
    { label: 'HLABプロジェクター（スタッフ・運営委員のみ）', email: 'c_188ftihvde6uujfggtq040ogg0v2g@resource.calendar.google.com' },
    { label: 'モニターディスプレイ', email: 'c_1887bv9bcg7v8ho2mvj1squdgbotc4g8d0mmoob25phmu@resource.calendar.google.com' },
];

// デフォルトのイベント色（カレンダーの色が取れなかったとき用）
const POST_DEFAULT_COLOR = '#CB1B3B';

/** シークレットが一致しなければ例外にする */
function checkSecret_(secret) {
    const expected = PropertiesService.getScriptProperties().getProperty('POST_SECRET');
    if (!expected) throw new Error('スクリプト プロパティ POST_SECRET が未設定です');
    if (secret !== expected) throw new Error('unauthorized');
}

function json_(value) {
    return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}

/**
 * Webアプリ エンドポイント(GET)
 * ?action=events で予定の一覧、?action=config で投稿フォーム用の設定(カレンダー/ROOM)を返す
 */
function doGet(e) {
    try {
        const params = (e && e.parameter) || {};
        checkSecret_(params.secret);

        if (params.action === 'config') {
            return json_({ success: true, config: getPostConfig_() });
        }
        if (params.action === 'events') {
            const from = new Date(params.from);
            const to = new Date(params.to);
            if (isNaN(from.getTime()) || isNaN(to.getTime()) || to <= from) {
                throw new Error('from / to が不正です');
            }
            if (to.getTime() - from.getTime() > SYNC_MAX_DAYS * 24 * 60 * 60 * 1000) {
                throw new Error('期間が長すぎます（最大 ' + SYNC_MAX_DAYS + ' 日）');
            }
            return json_({ success: true, events: fetchEventsFromCalendar_(from, to) });
        }
        throw new Error('action が不正です');
    } catch (err) {
        return json_({ success: false, error: err.toString() });
    }
}

/**
 * Webアプリ エンドポイント(POST)
 * 新 API の POST /calendar-events から呼ばれ、Googleカレンダーにイベントを作成する。
 * body(JSON): { secret, calendarKey, title, description, location, roomEmail, attendees,
 *               isAllDay, dateKey('yyyy-MM-dd'), startISO, endISO }
 */
function doPost(e) {
    const output = ContentService.createTextOutput();
    output.setMimeType(ContentService.MimeType.JSON);

    try {
        const body = JSON.parse(e.postData.contents);

        checkSecret_(body.secret);

        const calDef = POST_CALENDARS[body.calendarKey];
        if (!calDef) {
            throw new Error('カレンダーの指定が不正です: ' + body.calendarKey);
        }

        const title = (body.title || '').trim();
        if (!title) {
            throw new Error('タイトルは必須です');
        }

        // カレンダーIDで確実に特定（名前は表示用）
        const cal = CalendarApp.getCalendarById(calDef.id);
        if (!cal) {
            throw new Error('カレンダーが見つからないかアクセス権限がありません: ' + calDef.name + ' (' + calDef.id + ')');
        }

        // ROOMのラベルを location に補完（明示指定があればそちらを優先）
        let location = (body.location || '').trim();
        let roomEmail = (body.roomEmail || '').trim();
        if (roomEmail) {
            const room = ROOMS.find(r => r.email === roomEmail);
            if (room && !location) location = room.label;
        }

        const options = {};
        if (body.description) options.description = String(body.description);
        if (location) options.location = location;

        let event;
        if (body.isAllDay) {
            // 'yyyy-MM-dd' をローカル日付として解釈
            const parts = String(body.dateKey).split('-').map(Number);
            const day = new Date(parts[0], parts[1] - 1, parts[2]);
            event = cal.createAllDayEvent(title, day, options);
        } else {
            const start = new Date(body.startISO);
            const end = new Date(body.endISO);
            if (isNaN(start.getTime()) || isNaN(end.getTime()) || end <= start) {
                throw new Error('開始/終了時刻が不正です');
            }
            event = cal.createEvent(title, start, end, options);
        }

        // ROOM(リソース)をゲストとして追加 → 空いていれば自動で予約される
        if (roomEmail) {
            try { event.addGuest(roomEmail); } catch (gErr) { Logger.log('addGuest失敗: ' + gErr); }
        }

        // 招待するユーザーをゲストとして追加（重複はroomEmailと合わせてSetで除外）
        const attendees = Array.isArray(body.attendees) ? body.attendees : [];
        const invitedEmails = new Set();
        attendees.forEach(email => {
            const trimmed = String(email || '').trim();
            if (!trimmed || trimmed === roomEmail || invitedEmails.has(trimmed)) return;
            invitedEmails.add(trimmed);
            try { event.addGuest(trimmed); } catch (gErr) { Logger.log('addGuest失敗(' + trimmed + '): ' + gErr); }
        });

        output.setContent(JSON.stringify({ success: true, event: toEventDto_(event, cal) }));
    } catch (err) {
        output.setContent(JSON.stringify({ success: false, error: err.toString() }));
    }
    return output;
}

/** 投稿フォーム用の設定(カレンダー選択肢とROOM一覧)を返す（カレンダーIDは外部に出さない） */
function getPostConfig_() {
    const calendars = Object.keys(POST_CALENDARS).map(key => ({ key: key, name: POST_CALENDARS[key].name }));
    return { calendars: calendars, rooms: ROOMS };
}

/** 作成したイベントを CalendarEvent 互換のDTOに変換（楽観的表示用） */
function toEventDto_(event, cal) {
    const tz = Session.getScriptTimeZone();
    const startDt = event.getStartTime();
    const endDt = event.getEndTime();
    let color = POST_DEFAULT_COLOR;
    try { color = cal.getColor() || POST_DEFAULT_COLOR; } catch (ignore) { /* noop */ }
    return {
        id: String(event.getId()),
        calendarName: cal.getName(),
        title: event.getTitle(),
        description: event.getDescription() || '',
        location: event.getLocation() || '',
        startISO: startDt.toISOString(),
        endISO: endDt.toISOString(),
        dateKey: Utilities.formatDate(startDt, tz, 'yyyy-MM-dd'),
        startTime: Utilities.formatDate(startDt, tz, 'HH:mm'),
        endTime: Utilities.formatDate(endDt, tz, 'HH:mm'),
        displayDate: Utilities.formatDate(startDt, tz, 'M/d'),
        isAllDay: event.isAllDayEvent(),
        color: color,
        isRecurring: event.isRecurringEvent()
    };
}

/**
 * 共有カレンダーの予定を取得する（スクリプトの持ち主が購読している、自分の持ち物でないカレンダーすべて）。
 * 予定が範囲に少しでも重なっていれば含まれる。繰り返し予定は回ごとに同じ id で現れる
 */
function fetchEventsFromCalendar_(from, to) {
    const allEvents = [];

    CalendarApp.getAllCalendars().forEach(cal => {
        // ROOM(リソース)カレンダーは予約状況の羅列なので対象外
        if (cal.getId().endsWith('@resource.calendar.google.com')) return;
        if (cal.isOwnedByMe()) return;
        cal.getEvents(from, to).forEach(event => allEvents.push(toEventDto_(event, cal)));
    });

    return allEvents.sort((a, b) => a.startISO.localeCompare(b.startISO));
}

/**
 * 【設定用ヘルパー】アクセスできる全カレンダーの ID と名前をログに出す。
 * Apps Script エディタでこの関数を実行 →「実行ログ」で確認。
 * ROOM(リソース)は c_xxxx@resource.calendar.google.com 形式のIDで表示される。
 * ここで確認したIDを ROOMS / POST_CALENDARS に設定する。
 */
function listAllCalendarIds() {
    CalendarApp.getAllCalendars().forEach(cal => {
        Logger.log(cal.getName() + '  =>  ' + cal.getId());
    });
}

/**
 * 【移行用】旧版が作ったスプレッドシート同期のトリガー（syncEventsToSheet）を消す。
 * 差し替え後に一度だけエディタから実行する
 */
function removeOldTriggers() {
    ScriptApp.getProjectTriggers().forEach(trigger => {
        if (trigger.getHandlerFunction() === 'syncEventsToSheet') {
            ScriptApp.deleteTrigger(trigger);
            Logger.log('削除: ' + trigger.getHandlerFunction());
        }
    });
}
