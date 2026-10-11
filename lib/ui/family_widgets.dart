import 'package:flutter/material.dart';
import '../data/accounts.dart';
import '../models.dart';
import 'motion.dart';
import 'theme.dart';
import 'member_avatar_art.dart';

const familyIcons = [
  Icons.favorite_rounded,
  Icons.star_rounded,
  Icons.pets_rounded,
  Icons.local_florist_rounded,
  Icons.nightlight_round,
  Icons.wb_sunny_rounded,
];

class FamilyAvatarIcon extends StatelessWidget {
  const FamilyAvatarIcon(this.avatar, {super.key, this.size = 34});
  final int avatar;
  final double size;
  @override
  Widget build(BuildContext context) {
    final id = avatar >= 0 && avatar < familyAvatarLabels.length ? avatar : 0;
    return id < familyIcons.length
        ? Icon(familyIcons[id], color: teal, size: size * .6)
        : FamilyPortrait(kind: id - familyIcons.length, size: size);
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.member, {super.key, this.size = 34});
  final FamilyMember member;
  final double size;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: pale,
    child: FamilyAvatarIcon(member.avatar, size: size),
  );
}

Future<(String, int)?> editMember(
  BuildContext context, {
  FamilyMember? member,
}) async {
  return showDialog<(String, int)>(
    context: context,
    animationStyle: AnimationStyle(
      duration: motionTime(context, 280),
      reverseDuration: motionTime(context, 180),
      curve: Curves.easeOutCubic,
    ),
    builder: (_) => _MemberEditor(member: member),
  );
}

class _MemberEditor extends StatefulWidget {
  const _MemberEditor({this.member});
  final FamilyMember? member;
  @override
  State<_MemberEditor> createState() => _MemberEditorState();
}

class _MemberEditorState extends State<_MemberEditor> {
  late final name = TextEditingController(text: widget.member?.name);
  late int avatar = widget.member?.avatar ?? 13;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.member == null
          ? 'A place for someone you love.'
          : 'Their little profile.',
    ),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name or nickname',
              errorText: error,
            ),
          ),
          const SizedBox(height: 14),
          const Text('Pick their little face'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [7, 8, 9, 10, 6, 11, 12, 13].map(_avatarChoice).toList(),
          ),
          const SizedBox(height: 18),
          const Text('Or a favourite little symbol'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(familyIcons.length, _avatarChoice),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Maybe later'),
      ),
      MotionPress(
        child: FilledButton(
          onPressed: () {
            if (name.text.trim().isEmpty) {
              setState(() => error = 'What should we call them?');
              return;
            }
            Navigator.pop(context, (name.text.trim(), avatar));
          },
          child: const Text('Save profile'),
        ),
      ),
    ],
  );

  Widget _avatarChoice(int id) => MotionPress(
    child: ChoiceChip(
      avatar: FamilyAvatarIcon(id, size: 30),
      avatarBoxConstraints: const BoxConstraints.tightFor(
        width: 30,
        height: 30,
      ),
      label: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Text(familyAvatarLabels[id]),
        ),
      ),
      selected: avatar == id,
      onSelected: (_) => setState(() => avatar = id),
    ),
  );
}

Future<void> showFamilySignIn(BuildContext context, FamilyAccounts accounts) =>
    showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: AnimationStyle(
        duration: motionTime(context, 360),
        reverseDuration: motionTime(context, 240),
      ),
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: card,
      builder: (_) => _AccountForm(accounts: accounts),
    );

class _AccountForm extends StatefulWidget {
  const _AccountForm({required this.accounts});
  final FamilyAccounts accounts;
  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool creating = false, busy = false, hidden = true;
  String? error;
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (creating) {
        await widget.accounts.create(email.text, password.text);
      } else {
        await widget.accounts.signIn(email.text, password.text);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = accountError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              creating
                  ? 'A little home for your family.'
                  : 'Welcome back, family.',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'One account, separate profiles for everyone. Sign in on another phone to see your family’s saved readings.',
              style: TextStyle(color: muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Family email'),
              validator: (v) => v == null || !v.contains('@')
                  ? 'Enter an email address.'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: password,
              enabled: !busy,
              obscureText: hidden,
              autofillHints: [
                creating ? AutofillHints.newPassword : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  tooltip: hidden ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: Icon(
                    hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (v) => v == null || v.length < 6
                  ? 'Use at least 6 characters.'
                  : null,
            ),
            if (creating) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: confirm,
                enabled: !busy,
                obscureText: hidden,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
                validator: (v) =>
                    v != password.text ? 'Passwords don’t match yet.' : null,
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error!, style: const TextStyle(color: amber)),
              ),
            const SizedBox(height: 18),
            MotionPress(
              child: FilledButton(
                onPressed: busy ? null : submit,
                child: Text(
                  busy
                      ? 'One moment…'
                      : creating
                      ? 'Create family account'
                      : 'Sign in',
                ),
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      creating = !creating;
                      error = null;
                    }),
              child: Text(
                creating
                    ? 'Already have an account? Sign in'
                    : 'New here? Create a family account',
              ),
            ),
            if (!creating)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!email.text.contains('@')) {
                          setState(
                            () => error = 'Enter your family email first.',
                          );
                          return;
                        }
                        setState(() => busy = true);
                        try {
                          await widget.accounts.reset(email.text);
                          if (mounted) {
                            setState(
                              () => error =
                                  'If an account uses this email, you’ll receive a reset link.',
                            );
                          }
                        } catch (e) {
                          if (mounted) setState(() => error = accountError(e));
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Forgot password?'),
              ),
          ],
        ),
      ),
    ),
  );
}
