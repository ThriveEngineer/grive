import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skyclad/providers/providers.dart';

import 'package:skyclad/main.dart';
import 'package:skyclad/view/timeline.dart';

class LoginScreen extends ConsumerWidget {
  LoginScreen({Key? key}) : super(key: key);

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ScopedReader を WidgetRef に変更
    final isLoggedIn = ref.watch(loginStateProvider);

    if (isLoggedIn) {
      final goRouter = GoRouter.of(context);
      goRouter.go('/');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: Colors.blue[600],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _usernameController, // 追加
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'Enter your username',
                ),
              ),
              const SizedBox(height: 16.0),
              TextField(
                controller: _passwordController, // 追加
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter your password',
                ),
              ),
              const SizedBox(height: 32.0),
              ElevatedButton(
                onPressed: () async {
                  // 入力されたIDとパスワードを取得
                  final id = _usernameController.text.trim();
                  final password = _passwordController.text.trim();

                  // ログイン処理を実行
                  try {
                    await ref
                        .read(loginStateProvider.notifier)
                        .login(id, password);

                    ref.read(isLoggedInProvider.notifier).setLoggedIn(true);

                    // ログインに成功した場合、メイン画面に遷移
                    // ignore: use_build_context_synchronously
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MyApp(),
                      ),
                    );
                  } catch (e) {
                    // ログインに失敗した場合の処理
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}