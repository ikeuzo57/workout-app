/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (C) 2020, 2021 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * wger Workout Manager is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/models/exercises/exercise.dart';
import 'package:wger/theme/theme.dart';
import 'package:wger/widgets/routines/gym_mode/navigation.dart';

class TimerWidget extends StatefulWidget {
  final PageController _controller;
  final double _ratioCompleted;
  final Map<Exercise, int> _exercisePages;

  const TimerWidget(
    this._controller,
    this._ratioCompleted,
    this._exercisePages,
  );

  @override
  _TimerWidgetState createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<TimerWidget> {
  late DateTime _startTime;
  final _maxSeconds = 600;
  late Timer _uiTimer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();

    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // ignore: no-empty-block, avoid-empty-setstate
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(_startTime).inSeconds;
    final displaySeconds = elapsed > _maxSeconds ? _maxSeconds : elapsed;
    final displayTime = DateTime(2000, 1, 1, 0, 0, 0).add(Duration(seconds: displaySeconds));

    return Column(
      children: [
        NavigationHeader(
          AppLocalizations.of(context).pause,
          widget._controller,
          exercisePages: widget._exercisePages,
        ),
        Expanded(
          child: Center(
            child: Text(
              DateFormat('m:ss').format(displayTime),
              style: Theme.of(context).textTheme.displayLarge!.copyWith(color: wgerPrimaryColor),
            ),
          ),
        ),
        NavigationFooter(widget._controller, widget._ratioCompleted),
      ],
    );
  }
}

class TimerCountdownWidget extends StatefulWidget {
  final PageController _controller;
  final double _ratioCompleted;
  final int _seconds;
  final Map<Exercise, int> _exercisePages;

  const TimerCountdownWidget(
    this._controller,
    this._seconds,
    this._ratioCompleted,
    this._exercisePages,
  );

  @override
  _TimerCountdownWidgetState createState() => _TimerCountdownWidgetState();
}

class _TimerCountdownWidgetState extends State<TimerCountdownWidget> {
  late DateTime _endTime;
  late Timer _uiTimer;

  @override
  void initState() {
    super.initState();
    _endTime = DateTime.now().add(Duration(seconds: widget._seconds));

    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // ignore: no-empty-block, avoid-empty-setstate
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _endTime.difference(DateTime.now());
    final remainingSeconds = remaining.inSeconds <= 0 ? 0 : remaining.inSeconds;
    final displayTime = DateTime(2000, 1, 1, 0, 0, 0).add(Duration(seconds: remainingSeconds));

    return Column(
      children: [
        NavigationHeader(
          AppLocalizations.of(context).pause,
          widget._controller,
          exercisePages: widget._exercisePages,
        ),
        Expanded(
          child: Center(
            child: Text(
              DateFormat('m:ss').format(displayTime),
              style: Theme.of(context).textTheme.displayLarge!.copyWith(color: wgerPrimaryColor),
            ),
          ),
        ),
        NavigationFooter(widget._controller, widget._ratioCompleted),
      ],
    );
  }
}
