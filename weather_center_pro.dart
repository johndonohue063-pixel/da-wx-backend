import 'package:flutter/material.dart';

class WeatherCenterPro extends StatefulWidget {
  const WeatherCenterPro({super.key});
  @override
  State<WeatherCenterPro> createState() => _WeatherCenterProState();
}

class _WeatherCenterProState extends State<WeatherCenterPro>{
  // ---- State ----
  int _dayOffset = 0;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  // Filters
  String _scope = 'Nationwide'; // Nationwide, Region, State
  String? _region;              // Only when scope == Region
  String? _state;               // Only when scope == State
  double _sustained = 35;       // mph
  double _gust = 50;            // mph

  static const _brandOrange = Color(0xFFFF6A00);
  static const _regions = <String>[
    'Northeast','Mid-Atlantic','Southeast','Gulf','Midwest','Plains','Southwest','West','Pacific NW'
  ];

  static const _states = <String>[
    'AL','AR','AZ','CA','CO','CT','DC','DE','FL','GA','IA','ID','IL','IN','KS','KY','LA','MA','MD','ME','MI','MN',
    'MO','MS','MT','NC','ND','NE','NH','NJ','NM','NV','NY','OH','OK','OR','PA','RI','SC','SD','TN','TX','UT','VA',
    'VT','WA','WI','WV','WY'
  ];

  @override
  Widget build(BuildContext context){
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Weather Center Pro'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: <Widget>[
          _section('Threshold', _thresholdUI()),
          const SizedBox(height: 12),
          _filtersSection(),
          const SizedBox(height: 12),
          if(_loading) _loadingList()
          else if(_error != null) _errorPane(_error!)
          else _resultsPane(),
        ],
      ),
    );
  }

  // ---------- UI sections ----------
  Widget _section(String title, Widget child){
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _thresholdUI(){
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rowLabelValue('Sustained wind', '${_sustained.round()} mph'),
          Slider(
            value: _sustained, min: 10, max: 80, divisions: 70,
            onChanged: (v)=> setState(()=> _sustained = v),
          ),
          const SizedBox(height: 6),
          _rowLabelValue('Gusts', '${_gust.round()} mph'),
          Slider(
            value: _gust, min: 20, max: 120, divisions: 100,
            onChanged: (v)=> setState(()=> _gust = v),
          ),
        ],
      ),
    );
  }

  Widget _filtersSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _rowLabelValue('Days out', 'D$_dayOffset'),
          Slider(
            min: 0, max: 4, divisions: 4, value: _dayOffset.toDouble(),
            onChanged: (v){ setState(()=>_dayOffset = v.round()); },
          ),
          const SizedBox(height: 8),

          // Scope picker
          _label('Scope'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: ['Nationwide','Region','State'].map((s) {
              final selected = _scope == s;
              return ChoiceChip(
                label: Text(s),
                selected: selected,
                onSelected: (_)=> setState(()=> _scope = s..toString()),
                labelStyle: TextStyle(color: selected ? Colors.black : Colors.white70),
                selectedColor: _brandOrange,
                backgroundColor: const Color(0xFF1A1A1A),
                shape: StadiumBorder(side: BorderSide(color: selected ? _brandOrange : const Color(0xFF2A2A2A))),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Region dropdown
          if(_scope == 'Region') ...[
            _label('Region'),
            const SizedBox(height: 6),
            _darkDropdown<String>(
              value: _region,
              hint: 'Select region',
              items: _regions,
              onChanged: (v)=> setState(()=> _region = v),
            ),
            const SizedBox(height: 12),
          ],

          // State dropdown
          if(_scope == 'State') ...[
            _label('State'),
            const SizedBox(height: 6),
            _darkDropdown<String>(
              value: _state,
              hint: 'Select state',
              items: _states,
              onChanged: (v)=> setState(()=> _state = v),
            ),
            const SizedBox(height: 12),
          ],

          // Run button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _runForecast,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: _brandOrange.withOpacity(0.15),
                side: const BorderSide(color: _brandOrange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: const Icon(Icons.bolt),
              label: const Text('Run'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Actions ----------
  Future<void> _runForecast() async {
    setState(()=> _loading = true);
    try {
      // TODO: call your backend. For now, mock 3 rows so UI looks alive.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final scopeDesc = _scope == 'Nationwide'
          ? 'USA'
          : _scope == 'Region' ? (_region ?? 'Region') : (_state ?? 'State');

      _rows = List.generate(3, (i) => {
        'scope': scopeDesc,
        'day': 'D$_dayOffset',
        'sustained': '${_sustained.round()}',
        'gust': '${_gust.round()}',
        'row': i+1,
      });
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(()=> _loading = false);
    }
  }

  // ---------- Small pieces ----------
  BoxDecoration _card() => BoxDecoration(
    color: const Color(0xFF111111),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: _brandOrange.withOpacity(0.4)),
  );

  Widget _rowLabelValue(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _label(label),
        Text(value, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _label(String text) {
    return Text(text, style: const TextStyle(color: Colors.white70));
  }

  Widget _darkDropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required void Function(T? v) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: DropdownButton<T>(
        value: value,
        hint: Text(hint, style: const TextStyle(color: Colors.white54)),
        isExpanded: true,
        dropdownColor: const Color(0xFF121212),
        underline: const SizedBox.shrink(),
        iconEnabledColor: Colors.white70,
        style: const TextStyle(color: Colors.white),
        items: items.map((e) => DropdownMenuItem<T>(
          value: e,
          child: Text(e.toString()),
        )).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // ---------- Result panes ----------
  Widget _loadingList()=> Column(
    children: List.generate(5, (_)=> Container(
      height: 56, margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(10),
      ),
    )),
  );

  Widget _errorPane(String msg){
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A0000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _brandOrange.withOpacity(0.7)),
      ),
      child: Text(msg, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _resultsPane(){
    if(_rows.isEmpty){
      return const Text('No results', style: TextStyle(color: Colors.white70));
    }
    return Column(
      children: _rows.map((r)=> Container(
        height: 64, margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${r['scope']}  ${r['day']}', style: const TextStyle(color: Colors.white)),
              Text('${r['sustained']} / ${r['gust']} mph', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      )).toList(),
    );
  }
}
