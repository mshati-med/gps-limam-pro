
(() => {
  "use strict";

  const SUPABASE_URL =
    "https://ttwsfugpqxuekiztusas.supabase.co";

  const KEY_NAME = "gps_limam_supabase_publishable_key";
  const SESSION_NAME = "gps_limam_supabase_session";
  const LOCAL_DATA = "gps_limam_pro_v2";

  const style = document.createElement("style");
  style.textContent = `
    #gps-cloud-btn {
      position:fixed; z-index:9999; top:125px; right:12px;
      padding:12px 15px; border:1px solid #38e08f;
      border-radius:14px; background:#101c2d; color:#9affc9;
      font-size:14px; font-weight:bold;
    }
    #gps-cloud-panel {
      display:none; position:fixed; z-index:10000; inset:0;
      background:#000b; padding:16px; align-items:center;
      justify-content:center; font-family:system-ui,sans-serif;
    }
    #gps-cloud-panel.open {display:flex}
    #gps-cloud-card {
      width:100%; max-width:440px; max-height:90vh;
      overflow:auto; background:#101c2d; color:#f4f8ff;
      border:1px solid #26384e; border-radius:20px; padding:18px;
    }
    #gps-cloud-card input {
      display:block; width:100%; box-sizing:border-box;
      padding:12px; margin:9px 0; border-radius:10px;
      border:1px solid #34475d; background:#091525;
      color:white; font-size:15px;
    }
    #gps-cloud-card button {
      padding:11px; margin:4px 2px; border:0;
      border-radius:10px; background:#38e08f;
      color:#062116; font-weight:bold;
    }
    #gps-cloud-message {font-size:13px;line-height:1.7}
  `;
  document.head.appendChild(style);

  const button = document.createElement("button");
  button.id = "gps-cloud-btn";
  button.textContent = "☁ الحساب السحابي";
  document.body.appendChild(button);

  const panel = document.createElement("div");
  panel.id = "gps-cloud-panel";
  panel.innerHTML = `
    <div id="gps-cloud-card" dir="rtl">
      <h3>الحساب والمزامنة</h3>
      <p>أدخل مفتاح Supabase العام الذي يبدأ بـ sb_publishable_.</p>
      <input id="gps-cloud-key" placeholder="sb_publishable_..."
        autocomplete="off">
      <button id="gps-cloud-save-key">حفظ المفتاح</button>
      <hr>
      <input id="gps-cloud-email" type="email"
        placeholder="البريد الإلكتروني">
      <input id="gps-cloud-password" type="password"
        placeholder="كلمة المرور">
      <button id="gps-cloud-signup">إنشاء حساب</button>
      <button id="gps-cloud-login">تسجيل الدخول</button>
      <hr>
      <button id="gps-cloud-sync">مزامنة المفضلة</button>
      <button id="gps-cloud-logout">تسجيل الخروج</button>
      <button id="gps-cloud-close">إغلاق</button>
      <p id="gps-cloud-message" role="status"></p>
    </div>`;
  document.body.appendChild(panel);

  const $ = id => document.getElementById(id);
  const message = text => $("gps-cloud-message").textContent = text;
  let session = read(SESSION_NAME, null);

  function read(key, fallback) {
    try {
      return JSON.parse(localStorage.getItem(key)) || fallback;
    } catch {
      return fallback;
    }
  }

  function apiKey() {
    return localStorage.getItem(KEY_NAME) || "";
  }

  function headers() {
    return {
      apikey: apiKey(),
      Authorization: "Bearer " +
        (session?.access_token || apiKey()),
      "Content-Type": "application/json"
    };
  }

  async function request(path, options = {}) {
    if (!apiKey().startsWith("sb_publishable_")) {
      throw Error("احفظ مفتاح Supabase العام أولًا.");
    }

    const response = await fetch(SUPABASE_URL + path, {
      ...options,
      headers: {...headers(), ...(options.headers || {})}
    });

    const raw = await response.text();
    let data;
    try { data = JSON.parse(raw); } catch { data = null; }

    if (!response.ok) {
      throw Error(data?.msg || data?.message ||
        data?.error_description || "فشل الاتصال بسوبابيس.");
    }
    return data;
  }

  async function authenticate(mode) {
    try {
      const email = $("gps-cloud-email").value.trim();
      const password = $("gps-cloud-password").value;

      if (!email || password.length < 6) {
        throw Error("أدخل بريدك وكلمة مرور من 6 أحرف على الأقل.");
      }

      const path = mode === "signup"
        ? "/auth/v1/signup"
        : "/auth/v1/token?grant_type=password";

      const data = await request(path, {
        method: "POST",
        body: JSON.stringify({email, password})
      });

      if (!data?.access_token) {
        message("إذا طُلب تأكيد البريد، افتح رسالة التأكيد ثم سجّل الدخول.");
        return;
      }

      session = data;
      localStorage.setItem(SESSION_NAME, JSON.stringify(data));
      message("تم تسجيل الدخول. يمكنك الآن مزامنة المفضلة.");
    } catch (error) {
      message(error.message);
    }
  }

  async function sync() {
    try {
      if (!session?.access_token || !session?.user?.id) {
        throw Error("سجّل الدخول أولًا.");
      }

      const local = read(LOCAL_DATA, {places: [], track: [], car: null});
      const places = Array.isArray(local.places) ? local.places : [];
      const uid = session.user.id;

      const query = "/rest/v1/favorite_places" +
        "?select=id,user_id,place_name,latitude,longitude,created_at" +
        "&user_id=eq." + encodeURIComponent(uid);

      const cloud = await request(query);
      const key = p =>
        String(p.place_name ?? p.name ?? "").trim().toLowerCase() +
        "|" + Number(p.latitude ?? p.ll?.[0]).toFixed(5) +
        "|" + Number(p.longitude ?? p.ll?.[1]).toFixed(5);

      const known = new Set(cloud.map(key));
      let added = 0;

      for (const place of places) {
        if (!place.ll || place.ll.length !== 2) continue;
        if (known.has(key(place))) continue;

        await request("/rest/v1/favorite_places", {
          method: "POST",
          headers: {"Prefer": "return=minimal"},
          body: JSON.stringify({
            user_id: uid,
            place_name: String(place.name || "مكان محفوظ"),
            latitude: Number(place.ll[0]),
            longitude: Number(place.ll[1])
          })
        });

        known.add(key(place));
        added++;
      }

      const fresh = await request(query);
      const merged = [...places];

      for (const place of fresh) {
        if (!known.has(key(place)) ||
            !merged.some(p => key(p) === key(place))) {
          merged.push({
            id: "cloud-" + place.id,
            cloudId: place.id,
            name: place.place_name,
            ll: [Number(place.latitude), Number(place.longitude)],
            created: Date.now()
          });
        }
      }

      localStorage.setItem(LOCAL_DATA, JSON.stringify({
        ...local,
        places: merged
      }));

      message("اكتملت المزامنة. أضيف " + added +
        " مكانًا إلى السحابة. أعد تحميل التطبيق لرؤية التغييرات.");
    } catch (error) {
      message("تعذرت المزامنة: " + error.message +
        " تحقق من أسماء الأعمدة وسياسات الجدول.");
    }
  }

  button.onclick = () => {
    panel.classList.add("open");
    $("gps-cloud-key").value = apiKey();
    message(session?.access_token
      ? "أنت مسجل الدخول."
      : "احفظ المفتاح العام ثم سجّل الدخول.");
  };

  $("gps-cloud-save-key").onclick = () => {
    const key = $("gps-cloud-key").value.trim();
    if (!key.startsWith("sb_publishable_")) {
      message("المفتاح يجب أن يبدأ بـ sb_publishable_.");
      return;
    }
    localStorage.setItem(KEY_NAME, key);
    message("تم حفظ المفتاح على هذا الجهاز.");
  };

  $("gps-cloud-signup").onclick = () => authenticate("signup");
  $("gps-cloud-login").onclick = () => authenticate("login");
  $("gps-cloud-sync").onclick = sync;

  $("gps-cloud-logout").onclick = () => {
    session = null;
    localStorage.removeItem(SESSION_NAME);
    message("تم تسجيل الخروج.");
  };

  $("gps-cloud-close").onclick = () => panel.classList.remove("open");
})();
