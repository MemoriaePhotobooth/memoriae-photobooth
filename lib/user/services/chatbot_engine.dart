import '../models/booth_package.dart';
import '../models/camera_rental.dart';
import 'booking_hours.dart';
import 'booking_repository.dart';
import 'payment_settings_repository.dart';

/// What a button under a bot message does when tapped.
enum ChatActionKind {
  /// Sends [ChatAction.payload] (or the label) as if the customer typed it.
  suggest,

  /// Switches to another tab/route of the User app.
  navigate,

  /// Forwards the conversation to staff via the existing `messages` thread.
  handoff,

  /// Opens the My Bookings screen (status, balance due, refund updates).
  myBookings,
}

class ChatAction {
  final String label;
  final ChatActionKind kind;
  final String? payload;
  final String? route;
  final Object? arguments;

  const ChatAction._(this.label, this.kind, {this.payload, this.route, this.arguments});

  const ChatAction.suggest(String label, {String? text})
      : this._(label, ChatActionKind.suggest, payload: text);

  const ChatAction.navigate(String label, String route, {Object? arguments})
      : this._(label, ChatActionKind.navigate, route: route, arguments: arguments);

  const ChatAction.handoff([String label = 'Talk to staff'])
      : this._(label, ChatActionKind.handoff);

  const ChatAction.myBookings([String label = 'Open My Bookings'])
      : this._(label, ChatActionKind.myBookings);
}

class ChatMessage {
  final String text;
  final bool fromBot;
  final List<ChatAction> actions;

  /// True when the text came from the Gemini API rather than the built-in
  /// rules (the panel labels these so customers know).
  final bool isAi;

  const ChatMessage({required this.text, required this.fromBot, this.actions = const [], this.isAi = false});

  const ChatMessage.user(String text) : this(text: text, fromBot: false);
}

/// The live price list the bot answers from. Built by the controller from
/// the same `pricing` collection Admin edits (see `PricingRepository`), with
/// the static `kPackages` / `kCameraOptions` as fallback — so the bot never
/// quotes a price that differs from what the Book / Rent screens show.
class ChatCatalog {
  final List<BoothPackage> packages;
  final List<CameraOption> cameras;

  /// Downpayment rules Admin set in `settings/payment`.
  final PaymentSettings payment;

  const ChatCatalog({required this.packages, required this.cameras, this.payment = PaymentSettings.defaults});

  static const ChatCatalog fallback = ChatCatalog(packages: kPackages, cameras: kCameraOptions);
}

class ChatReply {
  final ChatMessage message;

  /// True when the customer just asked for a human (so the controller keeps
  /// the *previous* question as handoff context instead of this one).
  final bool handoffRequest;

  /// True when no rule matched — the controller may then ask the AI instead.
  final bool isFallback;

  const ChatReply(this.message, {this.handoffRequest = false, this.isFallback = false});
}

/// Keyword-based intent matcher. No network, no API key, no cost — and it can
/// only ever say things that come from [ChatCatalog] or the constants in this
/// file, so it can't make up prices or policies.
///
/// Anything it doesn't recognise (refunds, rescheduling, discounts, travel
/// fees, ...) is deliberately routed to staff instead of guessed at.
class ChatbotEngine {
  ChatbotEngine._();

  // ---------------------------------------------------------------- public

  static ChatMessage greeting({bool tagalog = false}) => ChatMessage(
        fromBot: true,
        text: tagalog
            ? 'Hi! Ako ang Memoriae assistant. Matutulungan kita sa packages at presyo, camera rental, paano mag-book, at oras. Ano ang maitutulong ko?'
            : "Hi! I'm the Memoriae assistant. I can help with packages & prices, camera rentals, how to book, and booking hours. What would you like to know?",
        actions: _menu,
      );

  static ChatReply reply(String input, ChatCatalog catalog) {
    final t = _norm(input);
    final tl = _isTagalog(t);

    // 1. Wants a human.
    if (_has(t, const ['human', 'staff', 'agent', 'person', 'tao', 'kausap*', 'kausapin', 'admin', 'owner', 'support', 'customer service', 'talk to', 'speak to'])) {
      return ChatReply(
        ChatMessage(
          fromBot: true,
          text: tl
              ? 'Sige, ipapasa kita sa staff namin. Ipapadala ko ang huli mong tanong para hindi mo na ulitin.'
              : "Sure — I can pass this on to our staff. I'll send them your last question so you don't have to repeat it.",
          actions: const [ChatAction.handoff('Send to staff')],
        ),
        handoffRequest: true,
      );
    }

    // 2. Things only staff can see or decide.
    if (_has(t, const ['cancel*', 'resched*', 'change date', 'palit', 'ilipat', 'promo*', 'discount*', 'voucher*', 'travel fee', 'outside', 'province'])) {
      return ChatReply(ChatMessage(
        fromBot: true,
        text: tl
            ? 'Para diyan, staff namin ang makakasagot nang tama (hindi ko nakikita ang bookings mo o ang policies sa ganyan). Gusto mo bang ipasa ko?'
            : "That's something only our staff can answer properly — I can't see individual bookings or decide on things like cancellations, rescheduling, promos or travel fees. Want me to pass it on?",
        actions: const [ChatAction.handoff()],
      ));
    }

    // 2a. Status / balance / refunds: the My Bookings screen already shows
    // these live, so point customers there instead of tying up staff.
    if (_has(t, const ['my booking', 'my bookings', 'booking status', 'status', 'balance', 'refund*', 'ticket*'])) {
      return const ChatReply(ChatMessage(
        fromBot: true,
        text: 'Your booking status, any balance due, and refund updates are shown under My Bookings. '
            'Refunds are sent to your GCash — you can save your GCash refund account in Profile > Payment Methods.\n\n'
            'For questions about cancellation or refund policy, our staff can help.',
        actions: [ChatAction.myBookings(), ChatAction.handoff()],
      ));
    }

    // 3. Payment.
    if (_has(t, const ['gcash', 'payment', 'pay', 'bayad', 'bayaran', 'downpayment', 'down payment', 'dp', 'receipt*', 'deposit'])) {
      final mins = BookingRepository.holdDuration.inMinutes;
      return ChatReply(ChatMessage(
        fromBot: true,
        text: 'Payment is sent through GCash. To reserve your date you send ${paymentSummary(catalog.payment)}.'
            '${catalog.payment.downpaymentEnabled ? ' The balance is paid on the event day.' : ''}\n\n'
            'When you tap "Book Now & Hold Slot", your slot is held for $mins minutes — upload your GCash receipt screenshot before the hold ends. '
            'Staff then review it and approve your booking.\n\n'
            'For anything about amounts or payment problems, our staff can help.',
        actions: const [ChatAction.navigate('Go to Book', '/book'), ChatAction.handoff()],
      ));
    }

    // 3b. Which dates are free? The Calendar tab already shows this live.
    if (_has(t, const ['avail*', 'sched*', 'calendar', 'free date', 'open date', 'free dates', 'open dates', 'bakante'])) {
      return ChatReply(ChatMessage(
        fromBot: true,
        text: 'The Calendar tab shows which dates are still open and which are already booked.\n\n'
            'Event time slots: ${kTimeSlots.join(', ')}.\n\n'
            '${BookingHours.closedMessage}',
        actions: const [
          ChatAction.navigate('Open Calendar', '/calendar'),
          ChatAction.navigate('Book now', '/book'),
        ],
      ));
    }

    // 4. Hours / time slots.
    if (_has(t, const ['hours', 'open*', 'bukas', 'close*', 'sarado', 'anong oras', 'ano oras', 'oras ng', 'curfew', 'what time', 'slot*', 'time slot'])) {
      final closedNow = !BookingHours.isOpen();
      final buf = StringBuffer();
      if (closedNow) buf.writeln('Booking is closed right now.');
      buf.writeln(BookingHours.closedMessage);
      buf.writeln();
      buf.write('Event time slots: ${kTimeSlots.join(', ')}.');
      return ChatReply(ChatMessage(
        fromBot: true,
        text: buf.toString(),
        actions: const [ChatAction.navigate('Book now', '/book'), ChatAction.suggest('How to book', text: 'how to book')],
      ));
    }

    // 5. A specific package, by name.
    final named = _matchPackages(t, catalog.packages);
    if (named.length == 1) return ChatReply(_packageDetail(named.first));
    if (named.length > 1) return ChatReply(_packageList(named, intro: 'These match what you asked:'));

    // 6. Camera rental.
    if (_has(t, const ['camera*', 'rent*', 'hiram*', 'dslr', 'mirrorless', 'instant', 'film'])) {
      return ChatReply(_cameraList(catalog.cameras));
    }

    // 7. Add-ons.
    if (_has(t, const ['add on', 'add ons', 'addon*', 'extra', 'dagdag'])) {
      return ChatReply(_addOns());
    }

    // 8. Packages / pricing overview.
    if (_has(t, const ['package*', 'presyo', 'price*', 'pricing', 'magkano', 'rate*', 'how much', 'cost', 'offer*', 'menu', 'inclusion*'])) {
      return ChatReply(_packageList(catalog.packages));
    }

    // 9. How to book.
    if (_has(t, const ['book*', 'reserve*', 'reservation*', 'paano', 'pano', 'how to', 'steps', 'process'])) {
      return ChatReply(_howToBook(catalog));
    }

    // 10. Location.
    if (_has(t, const ['location', 'saan', 'where', 'venue', 'area', 'address'])) {
      return const ChatReply(ChatMessage(
        fromBot: true,
        text: "When you book, you pin your event location on a map (there's also a \"Use my location\" button). I don't have details on service areas or our studio address — our staff can tell you those.",
        actions: [ChatAction.navigate('Go to Book', '/book'), ChatAction.handoff()],
      ));
    }

    // 11. Help / about.
    if (_has(t, const ['help', 'tulong', 'options', 'what can you do', 'who are you', 'about'])) {
      return ChatReply(greeting(tagalog: tl));
    }

    // 12. Thanks / bye.
    if (_has(t, const ['thanks', 'thank*', 'salamat', 'ty'])) {
      return ChatReply(ChatMessage(
        fromBot: true,
        text: tl ? 'Walang anuman! May iba pa ba akong maitutulong?' : "You're welcome! Anything else I can help with?",
        actions: _menu,
      ));
    }
    if (_has(t, const ['bye', 'goodbye', 'paalam'])) {
      return ChatReply(ChatMessage(
        fromBot: true,
        text: tl ? 'Paalam! Kita-kits sa Memoriae.' : 'Bye! Hope to see you at Memoriae.',
      ));
    }

    // 13. Greeting (only if nothing above matched).
    if (_has(t, const ['hi', 'hello', 'hey', 'hola', 'kumusta', 'musta', 'good morning', 'good afternoon', 'good evening', 'magandang*'])) {
      return ChatReply(greeting(tagalog: tl));
    }

    // 14. Don't guess.
    return ChatReply(ChatMessage(
      fromBot: true,
      text: tl
          ? 'Pasensya na, hindi ko pa sigurado ang sagot diyan. Matutulungan kita sa packages at presyo, camera rental, paano mag-book, at oras — o pwede kitang i-connect sa staff.'
          : "Sorry, I'm not sure about that one. I can help with packages & prices, camera rentals, how to book and booking hours — or I can connect you with our staff.",
      actions: [..._menu.take(4), const ChatAction.handoff()],
    ), isFallback: true);
  }

  // ------------------------------------------------------------- answers

  static const List<ChatAction> _menu = [
    ChatAction.suggest('Packages & prices', text: 'packages'),
    ChatAction.suggest('Camera rental', text: 'camera rental'),
    ChatAction.suggest('How to book', text: 'how to book'),
    ChatAction.suggest('Booking hours', text: 'booking hours'),
    ChatAction.handoff(),
  ];

  static ChatMessage _packageList(List<BoothPackage> packages, {String intro = 'Here are our photobooth packages:'}) {
    final sorted = [...packages]..sort((a, b) => a.price.compareTo(b.price));
    final lines = sorted.map((p) => '• ${p.name}${p.duration.isEmpty ? '' : ' (${p.duration})'} — ${formatPeso(p.price)}').join('\n');
    return ChatMessage(
      fromBot: true,
      text: '$intro\n$lines\n\nTap a package to see what\'s included.',
      actions: [
        for (final p in sorted.take(4)) ChatAction.suggest(p.name, text: 'Tell me about ${p.name}'),
        const ChatAction.navigate('Book now', '/book'),
      ],
    );
  }

  static ChatMessage _packageDetail(BoothPackage p) {
    final includes = p.features.isEmpty ? '' : '\nIncludes: ${p.features.join(', ')}.';
    return ChatMessage(
      fromBot: true,
      text: '${p.name}${p.duration.isEmpty ? '' : ' — ${p.duration}'} for ${formatPeso(p.price)}.$includes',
      actions: [
        ChatAction.navigate('Book ${p.name}', '/book', arguments: BookingIntent(package: p)),
        const ChatAction.suggest('Other packages', text: 'packages'),
      ],
    );
  }

  static ChatMessage _cameraList(List<CameraOption> cameras) {
    final lines = cameras.map((c) => '• ${c.name} — ${formatPeso(c.dailyRate)} / 24 hrs\n   ${c.description}').join('\n');
    final lengths = kRentalDurationOptions.map((o) => o.label).join(', ');
    return ChatMessage(
      fromBot: true,
      text: 'Cameras you can rent:\n$lines\n\nRental lengths: $lengths. Shorter or longer rentals are pro-rated from the daily rate.',
      actions: const [ChatAction.navigate('Rent a camera', '/rent'), ChatAction.handoff()],
    );
  }

  static ChatMessage _addOns() {
    final lines = kAddOns.map((a) => '• ${a.name} — ${formatPeso(a.price)}\n   ${a.description}').join('\n');
    return ChatMessage(
      fromBot: true,
      text: 'Optional add-ons you can attach to a booking:\n$lines',
      actions: const [ChatAction.navigate('Book now', '/book'), ChatAction.suggest('Packages & prices', text: 'packages')],
    );
  }

  static ChatMessage _howToBook(ChatCatalog catalog) {
    final mins = BookingRepository.holdDuration.inMinutes;
    return ChatMessage(
      fromBot: true,
      text: 'Booking a photobooth:\n'
          '1. Pick your event date and time\n'
          '2. Pin your event location on the map\n'
          '3. Choose a package (and add-ons if you want)\n'
          '4. Tap "Book Now & Hold Slot" — your slot is held for $mins minutes\n'
          '5. Send ${paymentSummary(catalog.payment)} through GCash and upload the receipt before the hold runs out\n'
          '6. Staff review it and approve your booking\n\n'
          '${BookingHours.closedMessage}',
      actions: const [ChatAction.navigate('Start booking', '/book'), ChatAction.suggest('Packages & prices', text: 'packages')],
    );
  }

  // ------------------------------------------------------------- helpers

  /// "a 30% downpayment (or the full amount)" / "the full amount" — built
  /// from the rules Admin saved, so the bot never quotes a stale percentage.
  static String paymentSummary(PaymentSettings p) {
    if (!p.downpaymentEnabled) return 'the full amount';
    return 'a ${p.label} downpayment (or the full amount)';
  }

  static const Set<String> _genericNameWords = {'package', 'packages', 'photo', 'booth', 'photobooth', 'special', 'with', 'plus'};

  /// Packages whose distinctive name words (>= 5 letters) appear in [t].
  static List<BoothPackage> _matchPackages(String t, List<BoothPackage> packages) {
    final tokens = t.split(' ').toSet();
    return packages.where((p) {
      final words = _norm(p.name).split(' ').where((w) => w.length >= 5 && !_genericNameWords.contains(w));
      return words.any(tokens.contains);
    }).toList();
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ñ\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// True if [t] contains any of [keys]. A key is matched as a whole word or
  /// phrase; a trailing `*` makes it a prefix match ("book*" -> booking).
  static bool _has(String t, List<String> keys) {
    final padded = ' $t ';
    final tokens = t.split(' ');
    for (final k in keys) {
      if (k.endsWith('*')) {
        final prefix = k.substring(0, k.length - 1);
        if (tokens.any((w) => w.startsWith(prefix))) return true;
      } else if (padded.contains(' $k ')) {
        return true;
      }
    }
    return false;
  }

  static const Set<String> _tagalogWords = {
    'ako', 'ang', 'ng', 'mga', 'po', 'opo', 'paano', 'pano', 'magkano', 'saan', 'ano', 'bakit',
    'kumusta', 'musta', 'salamat', 'pwede', 'puwede', 'gusto', 'nga', 'naman', 'ba', 'lang',
    'kasi', 'oras', 'bukas', 'presyo', 'hiram', 'hiramin', 'magandang', 'kayo', 'namin', 'niyo',
  };

  static bool _isTagalog(String t) => t.split(' ').any(_tagalogWords.contains);
}