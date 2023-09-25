import 'package:flutter/material.dart';

import 'user_model.dart';

class UserWidget extends StatelessWidget {
  const UserWidget({
    super.key,
    required this.user,
  });

  final UserModel user;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints.loose(const Size(500, 500)),
          child: ListenableBuilder(
            listenable: user,
            builder: (context, child) => Column(
              children: [
                Text(user.syncValue),
                Slider(
                  value: user.value,
                  onChanged: _valueChanged,
                  min: 0,
                  max: 10,
                  divisions: 20,
                ),
                Table(
                  children: [
                    const TableRow(children: [
                      Text('Count'),
                      Text('Min'),
                      Text('Average'),
                      Text('Max'),
                    ]),
                    TableRow(children: [
                      Text(user.stats.count.toString()),
                      Text(user.stats.min.toString()),
                      Text(user.stats.average.toString()),
                      Text(user.stats.max.toString()),
                    ])
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  void _valueChanged(double value) {
    user.value = value;
  }
}
