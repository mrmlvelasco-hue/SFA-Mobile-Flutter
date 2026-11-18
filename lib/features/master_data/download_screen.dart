import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../auth/auth_state.dart';
import 'master_data_state.dart';

/// Shown after login until the master data is downloaded -- the RN app's DownloadData progress
/// modal. On failure: the error, Retry, and Log out (e.g. to sign in as someone else).
class DownloadScreen extends StatelessWidget {
  const DownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MasterDataState>();
    final failed = state.status == MasterDataStatus.failed;
    final percent = (state.progress * 100).clamp(0, 100).round();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('SFA',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: AppColors.primary)),
                const SizedBox(height: 32),
                Text(
                  failed ? 'Download failed' : 'Downloading data',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.blue),
                ),
                const SizedBox(height: 8),
                Text(
                  failed
                      ? 'The app needs today\'s data before it can be used offline.'
                      : 'Keep the app open. After this, the app works without internet for the rest of the day.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.grayLight),
                ),
                const SizedBox(height: 24),
                if (!failed) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      key: const Key('downloadProgress'),
                      value: state.status == MasterDataStatus.checking ? null : state.progress,
                      minHeight: 8,
                      color: AppColors.blue,
                      backgroundColor: AppColors.gray,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.status == MasterDataStatus.checking ? 'Checking saved data...' : '${state.step}  $percent%',
                    key: const Key('downloadStep'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.grayFont),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.redLight, borderRadius: BorderRadius.circular(8)),
                    child: Text(state.errorMessage ?? 'Download failed.',
                        key: const Key('downloadError'), style: const TextStyle(color: AppColors.red2)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: state.download, child: const Text('Retry')),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => context.read<AuthState>().logout(), child: const Text('Log out')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
