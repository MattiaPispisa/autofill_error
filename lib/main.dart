// Android autofill does not suggest the saved credentials on the username
// field when the field gets focus while the screen is still animating.
//
// Both cases push a login route that slides in. As soon as the route appears,
// an event moves its PageView to the login form, while the route is still
// sliding in. Then the username field gets focus:
//
//   1. Right away                                   -> no suggestions (bug)
//   2. After the page change and the route transition -> suggestions show

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Duration of the route transition and of the page change.
const _kAnimationDuration = Duration(milliseconds: 600);

void main() => runApp(const MaterialApp(home: HomePage()));

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _openLogin(BuildContext context, {required bool waitForAnimations}) {
    Navigator.of(context)
        .push(_slideInRoute(LoginScreen(waitForAnimations: waitForAnimations)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Autofill repro')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => _openLogin(context, waitForAnimations: false),
              child: const Text('1. Focus right away (bug)'),
            ),
            ElevatedButton(
              onPressed: () => _openLogin(context, waitForAnimations: true),
              child: const Text('2. Focus after the animations'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slides in from the right.
Route<void> _slideInRoute(Widget page) {
  return PageRouteBuilder<void>(
    transitionDuration: _kAnimationDuration,
    reverseTransitionDuration: _kAnimationDuration,
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.waitForAnimations});

  /// Whether to wait for the page change and the route transition before
  /// focusing the username field.
  final bool waitForAnimations;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Below 1, a thin part of the login form is always visible, so the form is
  // already built when the focus request arrives.
  final _pageController = PageController(viewportFraction: 0.99);
  final _usernameFocusNode = FocusNode();

  late final StreamSubscription<void> _stateSubscription;

  @override
  void initState() {
    super.initState();
    // Simulates a `BlocListener`: the screen reacts to a state that is emitted
    // as soon as the route opens, while the route is still sliding in.
    _stateSubscription = Stream<void>.value(null)
        .listen((_) => _showLoginForm());
  }

  Future<void> _showLoginForm() async {
    final pageChange = _pageController.nextPage(
      duration: _kAnimationDuration,
      curve: Curves.easeIn,
    );

    if (widget.waitForAnimations) {
      await pageChange;
      if (!mounted) {
        return;
      }
      await _waitForRouteTransition(context);
    }
    if (!mounted) {
      return;
    }

    _usernameFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _stateSubscription.cancel();
    _pageController.dispose();
    _usernameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.waitForAnimations ? '2. Wait' : '1. Bug'),
      ),
      body: PageView(
        controller: _pageController,
        children: [
          const Center(child: Text('Loading…')),
          LoginForm(usernameFocusNode: _usernameFocusNode),
        ],
      ),
    );
  }
}

/// Completes when the route of [context] has finished sliding in.
Future<void> _waitForRouteTransition(BuildContext context) {
  final animation = ModalRoute.of(context)?.animation;
  final isSlidingIn = animation?.status == AnimationStatus.forward;
  if (animation == null || !isSlidingIn) {
    return Future.value();
  }

  final completer = Completer<void>();
  void onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.forward) {
      return;
    }
    animation.removeStatusListener(onStatusChanged);
    completer.complete();
  }

  animation.addStatusListener(onStatusChanged);
  return completer.future;
}

class LoginForm extends StatelessWidget {
  const LoginForm({super.key, required this.usernameFocusNode});

  final FocusNode usernameFocusNode;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              focusNode: usernameFocusNode,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const TextField(
              obscureText: true,
              autofillHints: [AutofillHints.password],
              decoration: InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                TextInput.finishAutofillContext();
                Navigator.of(context).pop();
              },
              child: const Text('Log in'),
            ),
          ],
        ),
      ),
    );
  }
}
