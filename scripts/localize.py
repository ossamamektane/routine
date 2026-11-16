"""Writes the English, French and Arabic string files from the table below.

Run from the repository root after changing any text in the app:
    python3 scripts/localize.py
It fails if a string in the code has no translation, or if a translation's
placeholders (%@, %lld) don't match the original.
"""
import json
import os
import plistlib
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESOURCES = os.path.join(HERE, "..", "Routine", "Resources")

# English text → (French, Arabic)
T = {
    "%@ after waking": ("%@ après le réveil", "بعد %@ من الاستيقاظ"),
    "%@/mo": ("%@/mois", "%@/شهر"),
    "%lld of %lld": ("%lld sur %lld", "%lld من %lld"),
    "%lld of %lld done": ("%lld sur %lld faits", "تم %lld من %lld"),
    "%lld of %lld this month": ("%lld sur %lld ce mois-ci", "%lld من %lld هذا الشهر"),
    "%lld of %lld this week": ("%lld sur %lld cette semaine", "%lld من %lld هذا الأسبوع"),
    "%lld of %lld today": ("%lld sur %lld aujourd’hui", "%lld من %lld اليوم"),
    "10 minutes after you wake up": ("10 minutes après le réveil", "بعد 10 دقائق من الاستيقاظ"),
    "3 times a week, any days": ("3 fois par semaine, n’importe quel jour", "3 مرات في الأسبوع، في أي يوم"),
    "4 weeks after the last one": ("4 semaines après la dernière fois", "بعد 4 أسابيع من آخر مرة"),
    "A goal": ("Un objectif", "هدف"),
    "A number of times per day, week or month, whenever it suits you.": (
        "Un certain nombre de fois par jour, par semaine ou par mois, quand ça vous arrange.",
        "عدد من المرات في اليوم أو الأسبوع أو الشهر، في الوقت الذي يناسبك."),
    "About": ("À propos", "حول"),
    "About %@ a month · %@ a year": ("Environ %@ par mois · %@ par an", "حوالي %@ شهريًا · %@ سنويًا"),
    "Add": ("Ajouter", "إضافة"),
    "Add a Time": ("Ajouter une heure", "إضافة وقت"),
    "Add a bill": ("Ajouter une facture", "إضافة فاتورة"),
    "Add a cost to anything — rent, a subscription, a haircut — and Money shows what's coming up and what's left to pay this month.": (
        "Ajoutez un montant à n’importe quoi — loyer, abonnement, coiffeur — et Budget affiche ce qui arrive et ce qu’il reste à payer ce mois-ci.",
        "أضف مبلغًا لأي شيء — الإيجار، اشتراك، حلاقة — وسيعرض لك قسم المصاريف ما هو قادم وما تبقى للدفع هذا الشهر."),
    "Add a routine": ("Ajouter une routine", "إضافة روتين"),
    "Add an amount to anything to see what’s paid and what’s left this month.": (
        "Ajoutez un montant à n’importe quoi pour voir ce qui est payé et ce qu’il reste ce mois-ci.",
        "أضف مبلغًا لأي شيء لترى ما تم دفعه وما تبقى هذا الشهر."),
    "Add routines, bills and goals. Today shows what's due, so you don't have to remember.": (
        "Ajoutez des routines, des factures et des objectifs. Aujourd’hui affiche ce qui est à faire, pour que vous n’ayez pas à y penser.",
        "أضف روتينات وفواتير وأهدافًا. يعرض لك قسم اليوم ما يجب فعله، فلا تحتاج إلى التذكّر."),
    "Add your own": ("Créer le vôtre", "أضف بنفسك"),
    "After I Wake Up": ("Après mon réveil", "بعد استيقاظي"),
    "After the last time": ("Après la dernière fois", "بعد آخر مرة"),
    "After you wake up": ("Après le réveil", "بعد الاستيقاظ"),
    "All Currencies": ("Toutes les devises", "كل العملات"),
    "All done for now": ("Tout est fait pour l’instant", "أنجزت كل شيء حاليًا"),
    "Allow Notifications": ("Autoriser les notifications", "السماح بالإشعارات"),
    "Amount": ("Montant", "المبلغ"),
    "Anytime": ("N’importe quand", "في أي وقت"),
    "Appearance": ("Apparence", "المظهر"),
    "Ask At": ("Demander à", "السؤال في"),
    "At a Set Time": ("À une heure précise", "في وقت محدد"),
    "At the same time the day before, or at %@ if there’s no time.": (
        "La veille à la même heure, ou à %@ s’il n’y a pas d’heure.",
        "في اليوم السابق بنفس الوقت، أو الساعة %@ إن لم يكن هناك وقت."),
    "At the time": ("À l’heure prévue", "في الموعد"),
    "Automatic": ("Automatique", "تلقائي"),
    "Autopay": ("Prélèvement auto", "دفع تلقائي"),
    "Badge on App Icon": ("Pastille sur l’icône", "شارة على أيقونة التطبيق"),
    "Bill": ("Facture", "فاتورة"),
    "Bills in the same place": ("Les factures au même endroit", "الفواتير في المكان نفسه"),
    "Blue": ("Bleu", "أزرق"),
    "Brown": ("Marron", "بني"),
    "By routine": ("Par routine", "حسب الروتين"),
    "Cancel": ("Annuler", "إلغاء"),
    "Change": ("Modifier", "تغيير"),
    "Changes appear on your other devices signed in to the same Apple Account.": (
        "Les modifications apparaissent sur vos autres appareils connectés au même compte Apple.",
        "تظهر التغييرات على أجهزتك الأخرى المسجّلة بنفس حساب Apple."),
    "Check it off each time you do it. Today shows how close you are.": (
        "Cochez-le à chaque fois. Aujourd’hui montre où vous en êtes.",
        "ضع علامة عليه كل مرة تقوم به. يعرض لك قسم اليوم مدى تقدّمك."),
    "Color": ("Couleur", "اللون"),
    "Coming up": ("À venir", "القادم"),
    "Completed": ("Terminées", "المكتملة"),
    "Continue": ("Continuer", "متابعة"),
    "Cost": ("Coût", "التكلفة"),
    "Counted as paid on the due date, so you don’t need to check it off.": (
        "Compté comme payé à la date prévue, inutile de le cocher.",
        "يُحتسب مدفوعًا في تاريخ الاستحقاق، فلا داعي لوضع علامة عليه."),
    "Counts from the last time you did it, like a haircut 6 weeks after the last one.": (
        "Compte à partir de la dernière fois, comme une coupe 6 semaines après la précédente.",
        "يُحسب من آخر مرة قمت به، مثل الحلاقة بعد 6 أسابيع من آخر مرة."),
    "Currency": ("Devise", "العملة"),
    "Cyan": ("Cyan", "سماوي"),
    "Daily": ("Tous les jours", "يوميًا"),
    "Daily Nudge": ("Rappel quotidien", "تذكير يومي"),
    "Dark": ("Sombre", "داكن"),
    "Date": ("Date", "التاريخ"),
    "Days": ("Jours", "أيام"),
    "Delete": ("Supprimer", "حذف"),
    "Delete “%@”?": ("Supprimer « %@ » ?", "حذف «%@»؟"),
    "Details": ("Détails", "التفاصيل"),
    "Display": ("Affichage", "العرض"),
    "Done": ("Terminé", "تم"),
    "Done %@": ("Fait le %@", "تم %@"),
    "Done at %@": ("Fait à %@", "تم الساعة %@"),
    "Drink water": ("Boire de l’eau", "شرب الماء"),
    "Due %@": ("Prévu %@", "مستحق %@"),
    "Duplicate": ("Dupliquer", "تكرار"),
    "Earlier…": ("Plus tôt…", "في وقت أبكر…"),
    "Edit": ("Modifier", "تعديل"),
    "Every %@": ("Chaque %@", "كل %@"),
    "Every %lld days": ("Tous les %lld jours", "كل %lld يوم"),
    "Every %lld hours": ("Toutes les %lld heures", "كل %lld ساعة"),
    "Every %lld months": ("Tous les %lld mois", "كل %lld شهر"),
    "Every %lld weeks": ("Toutes les %lld semaines", "كل %lld أسبوع"),
    "Every %lld years": ("Tous les %lld ans", "كل %lld سنة"),
    "Every 2 hours after you wake up": ("Toutes les 2 heures après le réveil", "كل ساعتين بعد الاستيقاظ"),
    "Every day": ("Tous les jours", "كل يوم"),
    "Every day at %@": ("Tous les jours à %@", "كل يوم الساعة %@"),
    "Every hour": ("Toutes les heures", "كل ساعة"),
    "Every month": ("Tous les mois", "كل شهر"),
    "Every morning, every other week, 6 weeks after the last haircut, or 3 times a week.": (
        "Chaque matin, une semaine sur deux, 6 semaines après la dernière coupe, ou 3 fois par semaine.",
        "كل صباح، أو كل أسبوعين، أو بعد 6 أسابيع من آخر حلاقة، أو 3 مرات في الأسبوع."),
    "Every week": ("Toutes les semaines", "كل أسبوع"),
    "Every week at %@": ("Toutes les semaines à %@", "كل أسبوع الساعة %@"),
    "Every weekday": ("Du lundi au vendredi", "من الاثنين إلى الجمعة"),
    "Every weekend": ("Le week-end", "كل سبت وأحد"),
    "Every year": ("Tous les ans", "كل سنة"),
    "Everything still works and is saved on this iPhone. To sync, sign in to iCloud in the Settings app.": (
        "Tout fonctionne et reste enregistré sur cet iPhone. Pour synchroniser, connectez-vous à iCloud dans Réglages.",
        "كل شيء يعمل ويُحفظ على هذا الـiPhone. للمزامنة، سجّل الدخول إلى iCloud من تطبيق الإعدادات."),
    "Everything that needs doing today in one calm list. Check things off with a tap.": (
        "Tout ce qu’il y a à faire aujourd’hui, dans une liste claire. Cochez d’un simple toucher.",
        "كل ما عليك فعله اليوم في قائمة هادئة واحدة. أنجز المهام بلمسة."),
    "For routines that start when you wake up. If you haven’t tapped “I’m up” by this time, Routine asks once.": (
        "Pour les routines qui commencent au réveil. Si vous n’avez pas touché « Je suis debout » à cette heure-ci, Routine vous le demande une fois.",
        "للروتينات التي تبدأ عند استيقاظك. إن لم تضغط «استيقظت» حتى هذا الوقت، يسألك Routine مرة واحدة."),
    "Frequency": ("Fréquence", "التكرار"),
    "From": ("De", "من"),
    "Goal": ("Objectif", "هدف"),
    "Goals": ("Objectifs", "الأهداف"),
    "Good morning": ("Bonjour", "صباح الخير"),
    "Gray": ("Gris", "رمادي"),
    "Green": ("Vert", "أخضر"),
    "Haircut": ("Coiffeur", "حلاقة"),
    "Hourly": ("Toutes les heures", "كل ساعة"),
    "Hours": ("Heures", "ساعات"),
    "I'm not up yet": ("Pas encore debout", "لم أستيقظ بعد"),
    "I'm up": ("Je suis debout", "استيقظت"),
    "Icon": ("Icône", "الأيقونة"),
    "Icon and Color": ("Icône et couleur", "الأيقونة واللون"),
    "Ideas to start with": ("Des idées pour commencer", "أفكار للبدء"),
    "In 1 hour": ("Dans 1 heure", "بعد ساعة"),
    "In 3 hours": ("Dans 3 heures", "بعد 3 ساعات"),
    "In the morning": ("Le matin", "في الصباح"),
    "Indigo": ("Indigo", "نيلي"),
    "Just once": ("Une seule fois", "مرة واحدة فقط"),
    "Just one time. It stays on Today until it’s done.": (
        "Une seule fois. Reste dans Aujourd’hui jusqu’à ce que ce soit fait.",
        "مرة واحدة فقط. تبقى في قسم اليوم حتى تُنجَز."),
    "Language": ("Langue", "اللغة"),
    "Last time %@": ("Dernière fois %@", "آخر مرة %@"),
    "Later": ("Plus tard", "لاحقًا"),
    "Later · %@": ("Plus tard · %@", "لاحقًا · %@"),
    "Later…": ("Plus tard…", "لاحقًا…"),
    "Left to pay": ("Reste à payer", "المتبقي للدفع"),
    "Light": ("Clair", "فاتح"),
    "Make the bed": ("Faire le lit", "ترتيب السرير"),
    "Mark as done": ("Marquer comme fait", "وضع علامة كمنجز"),
    "Mint": ("Menthe", "نعناعي"),
    "Money": ("Budget", "المصاريف"),
    "Month": ("Mois", "الشهر"),
    "Monthly": ("Tous les mois", "شهريًا"),
    "Monthly amounts are averages, so a yearly bill counts as a twelfth each month.": (
        "Les montants mensuels sont des moyennes : une facture annuelle compte pour un douzième chaque mois.",
        "المبالغ الشهرية متوسطات، لذا تُحتسب الفاتورة السنوية جزءًا من اثني عشر كل شهر."),
    "Monthly bill, reminder the day before": ("Facture mensuelle, rappel la veille", "فاتورة شهرية، تذكير في اليوم السابق"),
    "Monthly, paid automatically": ("Mensuel, prélevé automatiquement", "شهريًا، يُدفع تلقائيًا"),
    "Months": ("Mois", "أشهر"),
    "Morning Check-In": ("Question du matin", "سؤال الصباح"),
    "Name": ("Nom", "الاسم"),
    "New Bill": ("Nouvelle facture", "فاتورة جديدة"),
    "New Goal": ("Nouvel objectif", "هدف جديد"),
    "New Routine": ("Nouvelle routine", "روتين جديد"),
    "New Task": ("Nouvelle tâche", "مهمة جديدة"),
    "Next %@": ("Prochaine fois : %@", "التالي: %@"),
    "Next 12 months": ("Les 12 prochains mois", "الأشهر الـ12 القادمة"),
    "Next Time": ("Prochaine fois", "المرة القادمة"),
    "Next at %@": ("Prochain à %@", "التالي الساعة %@"),
    "Next, Routine asks if it can send you reminders. You can change this anytime.": (
        "Routine va ensuite vous demander s’il peut vous envoyer des rappels. Vous pourrez changer d’avis à tout moment.",
        "بعد ذلك سيطلب Routine إذنك لإرسال التذكيرات. يمكنك تغيير ذلك في أي وقت."),
    "Next: %@": ("Prochaine fois : %@", "التالي: %@"),
    "No account": ("Aucun compte", "بلا حساب"),
    "No account and no ads. Your iCloud keeps your devices in sync.": (
        "Pas de compte, pas de pub. Votre iCloud synchronise vos appareils.",
        "بلا حساب وبلا إعلانات. يزامن iCloud الخاص بك أجهزتك."),
    "No account needed. Your routines sync privately through your own iCloud, and nothing is stored on anyone else’s servers.": (
        "Aucun compte nécessaire. Vos routines se synchronisent en privé via votre propre iCloud, et rien n’est stocké sur les serveurs de quelqu’un d’autre.",
        "لا حاجة إلى حساب. تتزامن روتيناتك بشكل خاص عبر iCloud الخاص بك، ولا يُخزَّن أي شيء على خوادم أي جهة أخرى."),
    "No costs yet": ("Aucun montant pour l’instant", "لا توجد مصاريف بعد"),
    "No data collected": ("Aucune donnée collectée", "لا يتم جمع أي بيانات"),
    "No routines yet": ("Aucune routine pour l’instant", "لا توجد روتينات بعد"),
    "Notes": ("Notes", "ملاحظات"),
    "Nothing else due today.": ("Rien d’autre à faire aujourd’hui.", "لا شيء آخر مستحق اليوم."),
    "Nothing here yet": ("Rien pour l’instant", "لا شيء هنا بعد"),
    "Notifications are turned off for Routine. You can turn them on in the Settings app.": (
        "Les notifications sont désactivées pour Routine. Vous pouvez les activer dans Réglages.",
        "الإشعارات متوقفة لتطبيق Routine. يمكنك تشغيلها من تطبيق الإعدادات."),
    "Off": ("Désactivé", "إيقاف"),
    "On a schedule": ("Selon un calendrier", "وفق جدول"),
    "On fixed days and times, like every morning or the 1st of the month.": (
        "Des jours et heures fixes, comme chaque matin ou le 1er du mois.",
        "في أيام وأوقات ثابتة، مثل كل صباح أو أول كل شهر."),
    "Once · %@": ("Une fois · %@", "مرة واحدة · %@"),
    "One-time": ("Ponctuel", "لمرة واحدة"),
    "Only on days you haven’t reached your goal yet.": (
        "Seulement les jours où l’objectif n’est pas encore atteint.",
        "فقط في الأيام التي لم تبلغ فيها هدفك بعد."),
    "Optional. Add an amount for bills and subscriptions to see them in Money.": (
        "Facultatif. Ajoutez un montant pour les factures et abonnements afin de les voir dans Budget.",
        "اختياري. أضف مبلغًا للفواتير والاشتراكات لتراها في المصاريف."),
    "Orange": ("Orange", "برتقالي"),
    "Overdue": ("En retard", "متأخر"),
    "Overdue since %@": ("En retard depuis %@", "متأخر منذ %@"),
    "Overdue · was due %@": ("En retard · prévu %@", "متأخر · كان مستحقًا %@"),
    "Paid": ("Payé", "المدفوع"),
    "Paid Automatically": ("Prélevé automatiquement", "يُدفع تلقائيًا"),
    "Pause": ("Mettre en pause", "إيقاف مؤقت"),
    "Paused": ("En pause", "متوقف مؤقتًا"),
    "Paused items stay in your list but don’t show up on Today or send reminders.": (
        "Les éléments en pause restent dans la liste mais n’apparaissent pas dans Aujourd’hui et n’envoient pas de rappels.",
        "تبقى العناصر المتوقفة في قائمتك لكنها لا تظهر في قسم اليوم ولا ترسل تذكيرات."),
    "Per day": ("Par jour", "في اليوم"),
    "Per month": ("Par mois", "في الشهر"),
    "Per week": ("Par semaine", "في الأسبوع"),
    "Period": ("Période", "الفترة"),
    "Pink": ("Rose", "وردي"),
    "Privacy": ("Confidentialité", "الخصوصية"),
    "Private and synced": ("Privé et synchronisé", "خاص ومتزامن"),
    "Purple": ("Violet", "بنفسجي"),
    "Recent": ("Récent", "الأحدث"),
    "Red": ("Rouge", "أحمر"),
    "Remind Me": ("Me rappeler", "ذكّرني"),
    "Remind me again": ("Me le rappeler", "ذكّرني مرة أخرى"),
    "Reminder": ("Rappel", "التذكير"),
    "Reminders": ("Rappels", "التذكيرات"),
    "Reminders are scheduled by your iPhone itself. Nothing is sent anywhere.": (
        "Les rappels sont programmés par votre iPhone lui-même. Rien n’est envoyé nulle part.",
        "يجدول جهاز iPhone التذكيرات بنفسه. لا يُرسل أي شيء إلى أي مكان."),
    "Reminders are scheduled by your iPhone, so they work offline. The badge shows what’s left to do today.": (
        "Les rappels sont programmés par votre iPhone et fonctionnent hors ligne. La pastille indique ce qu’il reste à faire aujourd’hui.",
        "يجدول جهاز iPhone التذكيرات، لذا تعمل دون اتصال. تعرض الشارة ما تبقى لفعله اليوم."),
    "Reminders stay on your iPhone": ("Les rappels restent sur votre iPhone", "التذكيرات تبقى على جهازك"),
    "Remove Time": ("Supprimer l’heure", "إزالة الوقت"),
    "Rent": ("Loyer", "الإيجار"),
    "Results": ("Résultats", "النتائج"),
    "Resume": ("Reprendre", "استئناف"),
    "Right when I wake up": ("Dès mon réveil", "فور استيقاظي"),
    "Routine": ("Routine", "روتين"),
    "Routine doesn’t collect, sell or share anything about you. There are no ads, no analytics and no trackers.": (
        "Routine ne collecte, ne vend et ne partage rien sur vous. Pas de pub, pas d’analyse, pas de traceurs.",
        "لا يجمع Routine أي شيء عنك ولا يبيعه ولا يشاركه. لا إعلانات ولا تحليلات ولا أدوات تتبّع."),
    "Routine speaks English, French and Arabic. Language opens the Settings app, where you can pick one just for Routine.": (
        "Routine parle anglais, français et arabe. Langue ouvre Réglages, où vous pouvez en choisir une rien que pour Routine.",
        "يدعم Routine الإنجليزية والفرنسية والعربية. يفتح زر اللغة تطبيق الإعدادات حيث يمكنك اختيار لغة لـRoutine وحده."),
    "Routines": ("Routines", "الروتينات"),
    "Routines that fit real life": ("Des routines adaptées à la vraie vie", "روتينات تناسب حياتك الحقيقية"),
    "Routine’s sync space is full, so new changes stay on this iPhone. Deleting old routines frees up space.": (
        "L’espace de synchronisation de Routine est plein : les nouvelles modifications restent sur cet iPhone. Supprimer d’anciennes routines libère de la place.",
        "مساحة المزامنة الخاصة بـRoutine ممتلئة، لذا تبقى التغييرات الجديدة على هذا الـiPhone. حذف الروتينات القديمة يوفّر مساحة."),
    "Save": ("Enregistrer", "حفظ"),
    "Search": ("Rechercher", "بحث"),
    "Settings": ("Réglages", "الإعدادات"),
    "Skip": ("Passer", "تخطي"),
    "Skipped": ("Passé", "تم التخطي"),
    "Starts": ("Début", "يبدأ"),
    "Streaming subscription": ("Abonnement streaming", "اشتراك بث"),
    "Suggested": ("Suggestions", "مقترحة"),
    "Synced with iCloud": ("Synchronisé avec iCloud", "متزامن مع iCloud"),
    "Take medication": ("Prendre ses médicaments", "تناول الدواء"),
    "Take out the trash": ("Sortir les poubelles", "إخراج القمامة"),
    "Tap + to add something you do regularly, a bill, or a goal.": (
        "Touchez + pour ajouter une habitude, une facture ou un objectif.",
        "اضغط + لإضافة شيء تفعله بانتظام أو فاتورة أو هدف."),
    "Tap when you're up. Your wake-up routines start from then.": (
        "Touchez quand vous êtes debout. Vos routines du réveil partent de là.",
        "اضغط عندما تستيقظ. تبدأ روتينات الاستيقاظ من تلك اللحظة."),
    "Tap “I'm up” when you're up and your morning routines will start.": (
        "Touchez « Je suis debout » au réveil et vos routines du matin commenceront.",
        "اضغط «استيقظت» عندما تستيقظ وستبدأ روتينات الصباح."),
    "Teal": ("Bleu-vert", "أزرق مخضر"),
    "The day before": ("La veille", "في اليوم السابق"),
    "Things without a time are grouped into one reminder at %@.": (
        "Les éléments sans heure sont regroupés dans un seul rappel à %@.",
        "تُجمع العناصر التي بلا وقت في تذكير واحد الساعة %@."),
    "This evening": ("Ce soir", "هذا المساء"),
    "This removes it and its history from all your devices.": (
        "Cela le supprime, avec son historique, de tous vos appareils.",
        "سيؤدي هذا إلى حذفه مع سجله من جميع أجهزتك."),
    "Time": ("Heure", "الوقت"),
    "To do: %lld · Done: %lld": ("À faire : %lld · Faits : %lld", "المتبقي: %lld · المنجز: %lld"),
    "Today": ("Aujourd’hui", "اليوم"),
    "Today at a glance": ("Aujourd’hui en un coup d’œil", "يومك في لمحة"),
    "Tomorrow": ("Demain", "غدًا"),
    "Tomorrow at %@": ("Demain à %@", "غدًا الساعة %@"),
    "Tomorrow morning": ("Demain matin", "صباح الغد"),
    "Turn On Notifications in Settings": ("Activer les notifications dans Réglages", "تشغيل الإشعارات من الإعدادات"),
    "Type": ("Type", "النوع"),
    "Undo": ("Annuler", "تراجع"),
    "Unit": ("Unité", "الوحدة"),
    "Until": ("Jusqu’à", "حتى"),
    "Untitled": ("Sans titre", "بلا عنوان"),
    "Up since %@": ("Debout depuis %@", "مستيقظ منذ %@"),
    "Version": ("Version", "الإصدار"),
    "Wake-up routines are timed from this.": (
        "Les routines du réveil sont calculées à partir de cette heure.",
        "تُحسب روتينات الاستيقاظ انطلاقًا من هذا الوقت."),
    "Waking Up": ("Réveil", "الاستيقاظ"),
    "Weekly": ("Toutes les semaines", "أسبوعيًا"),
    "Weeks": ("Semaines", "أسابيع"),
    "Welcome to Routine": ("Bienvenue dans Routine", "مرحبًا بك في Routine"),
    "When": ("Quand", "متى"),
    "When did you wake up?": ("Heure du réveil ?", "متى استيقظت؟"),
    "When you wake up": ("Au réveil", "عند الاستيقاظ"),
    "Woke up at": ("Réveil à", "استيقظت الساعة"),
    "Work out": ("Faire du sport", "ممارسة الرياضة"),
    "Yearly": ("Tous les ans", "سنويًا"),
    "Years": ("Ans", "سنوات"),
    "Yellow": ("Jaune", "أصفر"),
    "Yesterday": ("Hier", "أمس"),
    "You never sign up or log in. Your iCloud keeps your devices in sync.": (
        "Vous ne créez jamais de compte et ne vous connectez jamais. Votre iCloud synchronise vos appareils.",
        "لا تحتاج أبدًا إلى إنشاء حساب أو تسجيل الدخول. يزامن iCloud الخاص بك أجهزتك."),
    "Your iCloud, not our servers": ("Votre iCloud, pas nos serveurs", "iCloud الخاص بك، لا خوادمنا"),
    "Your routines are saved on your devices and in your private iCloud storage. Only you can see them.": (
        "Vos routines sont enregistrées sur vos appareils et dans votre stockage iCloud privé. Vous êtes la seule personne à pouvoir les voir.",
        "تُحفظ روتيناتك على أجهزتك وفي مساحة iCloud الخاصة بك. لا يراها أحد سواك."),
    "day %lld": ("le %lld", "يوم %lld"),
    "from %@ after waking": ("à partir de %@ après le réveil", "بدءًا من %@ بعد الاستيقاظ"),
    "from when you wake up": ("dès le réveil", "من لحظة الاستيقاظ"),
    "iCloud": ("iCloud", "iCloud"),
    "iCloud is off": ("iCloud est désactivé", "iCloud متوقف"),
    "iCloud sync is full": ("La synchro iCloud est pleine", "مساحة مزامنة iCloud ممتلئة"),
    "until %@": ("jusqu’à %@", "حتى %@"),
    "was due %@": ("prévu %@", "كان مستحقًا %@"),
    "weekdays": ("du lundi au vendredi", "من الاثنين إلى الجمعة"),
    "weekends": ("le week-end", "السبت والأحد"),
    "when you wake up": ("au réveil", "عند الاستيقاظ"),
}

# Text whose wording depends on the number: English, French and Arabic plural forms.
AR_FORMS = ("zero", "one", "two", "few", "many", "other")


def ar(noun_one, noun_two, noun_few, noun_many, noun_other, pattern):
    """Arabic forms. `pattern` contains {n} where the counted noun goes."""
    return {
        "zero": pattern.format(n="%lld " + noun_other),
        "one": pattern.format(n=noun_one),
        "two": pattern.format(n=noun_two),
        "few": pattern.format(n="%lld " + noun_few),
        "many": pattern.format(n="%lld " + noun_many),
        "other": pattern.format(n="%lld " + noun_other),
    }


HOUR = ("ساعة", "ساعتين", "ساعات", "ساعة", "ساعة")
DAY = ("يوم", "يومين", "أيام", "يومًا", "يوم")
WEEK = ("أسبوع", "أسبوعين", "أسابيع", "أسبوعًا", "أسبوع")
MONTH = ("شهر", "شهرين", "أشهر", "شهرًا", "شهر")
YEAR = ("سنة", "سنتين", "سنوات", "سنة", "سنة")

PLURALS = {
    # key: (English {one, other}, French {one, other}, Arabic forms)
    "%lld hours after last time": (
        {"one": "%lld hour after last time", "other": "%lld hours after last time"},
        {"one": "%lld heure après la dernière fois", "other": "%lld heures après la dernière fois"},
        ar(*HOUR, "بعد {n} من آخر مرة")),
    "%lld days after last time": (
        {"one": "%lld day after last time", "other": "%lld days after last time"},
        {"one": "%lld jour après la dernière fois", "other": "%lld jours après la dernière fois"},
        ar(*DAY, "بعد {n} من آخر مرة")),
    "%lld weeks after last time": (
        {"one": "%lld week after last time", "other": "%lld weeks after last time"},
        {"one": "%lld semaine après la dernière fois", "other": "%lld semaines après la dernière fois"},
        ar(*WEEK, "بعد {n} من آخر مرة")),
    "%lld months after last time": (
        {"one": "%lld month after last time", "other": "%lld months after last time"},
        {"one": "%lld mois après la dernière fois", "other": "%lld mois après la dernière fois"},
        ar(*MONTH, "بعد {n} من آخر مرة")),
    "%lld years after last time": (
        {"one": "%lld year after last time", "other": "%lld years after last time"},
        {"one": "%lld an après la dernière fois", "other": "%lld ans après la dernière fois"},
        ar(*YEAR, "بعد {n} من آخر مرة")),
    "%lld times a day": (
        {"one": "Once a day", "other": "%lld times a day"},
        {"one": "Une fois par jour", "other": "%lld fois par jour"},
        ar("مرة واحدة", "مرتين", "مرات", "مرة", "مرة", "{n} في اليوم")),
    "%lld times a week": (
        {"one": "Once a week", "other": "%lld times a week"},
        {"one": "Une fois par semaine", "other": "%lld fois par semaine"},
        ar("مرة واحدة", "مرتين", "مرات", "مرة", "مرة", "{n} في الأسبوع")),
    "%lld times a month": (
        {"one": "Once a month", "other": "%lld times a month"},
        {"one": "Une fois par mois", "other": "%lld fois par mois"},
        ar("مرة واحدة", "مرتين", "مرات", "مرة", "مرة", "{n} في الشهر")),
    # "Every N …" only ever gets N ≥ 2; Arabic still needs its dual and plural forms.
    "Every %lld hours": (None, None, ar(*HOUR, "كل {n}")),
    "Every %lld days": (None, None, ar(*DAY, "كل {n}")),
    "Every %lld weeks": (None, None, ar(*WEEK, "كل {n}")),
    "Every %lld months": (None, None, ar(*MONTH, "كل {n}")),
    "Every %lld years": (None, None, ar(*YEAR, "كل {n}")),
}

SPEC = re.compile(r"%(?:lld|@|d|ld|f|lf)")


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def write_strings(lang, entries):
    folder = os.path.join(RESOURCES, f"{lang}.lproj")
    os.makedirs(folder, exist_ok=True)
    lines = ["/* Generated by scripts/localize.py — edit the table there, then run it again. */", ""]
    for key in sorted(entries, key=lambda k: k.lower()):
        lines.append(f'"{escape(key)}" = "{escape(entries[key])}";')
    with open(os.path.join(folder, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def write_stringsdict(lang, plurals):
    folder = os.path.join(RESOURCES, f"{lang}.lproj")
    os.makedirs(folder, exist_ok=True)
    root = {}
    for key, forms in plurals.items():
        rule = {"NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld"}
        rule.update(forms)
        root[key] = {"NSStringLocalizedFormatKey": "%#@count@", "count": rule}
    with open(os.path.join(folder, "Localizable.stringsdict"), "wb") as f:
        plistlib.dump(root, f, sort_keys=True)


def main():
    out = subprocess.run([sys.executable, os.path.join(HERE, "extract_strings.py")], capture_output=True, text=True, check=True)
    keys = [e["key"] for e in json.loads(out.stdout)]
    problems = []

    for key in keys:
        if key not in T and key not in PLURALS:
            problems.append(f"No translation for: {key!r}")
    for key, (fr, ar_text) in T.items():
        want = SPEC.findall(key)
        for lang, text in (("fr", fr), ("ar", ar_text)):
            if SPEC.findall(text) != want:
                problems.append(f"Placeholders differ ({lang}): {key!r} → {text!r}")
    for key, (en, fr, ar_forms) in PLURALS.items():
        for lang, forms in (("en", en), ("fr", fr), ("ar", ar_forms)):
            if not forms:
                continue
            for name, text in forms.items():
                if len(SPEC.findall(text)) > 1 or any(s != "%lld" for s in SPEC.findall(text)):
                    problems.append(f"Bad plural placeholder ({lang}/{name}): {text!r}")
    unused = sorted(set(T) - set(keys))

    if problems:
        print("\n".join(problems))
        sys.exit(1)

    plural_only = {k for k, v in PLURALS.items() if v[0] is not None}
    write_strings("en", {k: k for k in keys if k not in plural_only})
    write_strings("fr", {k: T[k][0] for k in keys if k in T and k not in plural_only})
    write_strings("ar", {k: T[k][1] for k in keys if k in T})
    write_stringsdict("en", {k: v[0] for k, v in PLURALS.items() if v[0]})
    write_stringsdict("fr", {k: v[1] for k, v in PLURALS.items() if v[1]})
    write_stringsdict("ar", {k: v[2] for k, v in PLURALS.items() if v[2]})
    print(f"{len(keys)} strings written for en, fr and ar.")
    if unused:
        print("Not used in the code any more:", ", ".join(repr(u) for u in unused))


if __name__ == "__main__":
    main()
