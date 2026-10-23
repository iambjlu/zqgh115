import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chc115/main.dart';

void main() {
  testWidgets('歡迎畫面：標題、連線按鈕，模擬數據按鈕預設隱藏、長按連線後顯示', (tester) async {
    await tester.pumpWidget(const RideHudApp());
    await tester.pump();
    expect(find.text('自行車警示系統'), findsOneWidget);
    expect(find.text('連線'), findsOneWidget);
    expect(find.textContaining('MAC'), findsNothing);
    expect(find.text('使用模擬數據繼續'), findsNothing);

    await tester.longPress(find.text('連線'));
    await tester.pump();
    expect(find.text('使用模擬數據繼續'), findsOneWidget);

    await tester.tap(find.text('使用模擬數據繼續'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('20'), findsOneWidget);
    expect(find.text('BLE 板子模擬資料', findRichText: true, skipOffstage: false), findsNothing);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('斷線'), findsOneWidget);
    expect(find.text('模擬控制'), findsOneWidget);
  });

  testWidgets('離開再回來會回到歡迎頁', (tester) async {
    await tester.pumpWidget(const RideHudApp());
    await tester.pump();
    await tester.longPress(find.text('連線'));
    await tester.pump();
    await tester.tap(find.text('使用模擬數據繼續'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('20'), findsOneWidget);

    // 只有 inactive（例如下拉通知列）不會離開 HUD。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('20'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('自行車警示系統'), findsOneWidget);
    expect(find.text('20'), findsNothing);
  });
}
