class CrewLogic {
  static Map<String, dynamic> compute(
      {required double sustainedMph,
      required double gustMph,
      required int population}) {
    // Wind factor tiers (utility-friendly, conservative on metro)
    double wf = 1.0;
    if (sustainedMph < 15)
      wf = 0.5;
    else if (sustainedMph < 25)
      wf = 1.0;
    else if (sustainedMph < 35)
      wf = 1.6;
    else if (sustainedMph < 45)
      wf = 2.2;
    else
      wf = 3.0;
    if (gustMph >= 60)
      wf += 1.0;
    else if (gustMph >= 50)
      wf += 0.6;
    else if (gustMph >= 40) wf += 0.3;

    // Incidents: ~ per 10k customers scaled by wf
    final incidents =
        ((population / 10000.0) * wf).clamp(0, population / 5).toDouble();
    // Customers out (cap 8% hard ceiling, scale by wf)
    final customersOut =
        (population * 0.02 * (wf / 2)).clamp(0, population * 0.08).toDouble();
    // Crews: ~ 1 crew per 3 incidents, min 4
    final crews = (incidents / 3.0).ceil().clamp(4, 500);

    String threat = "Level 0";
    if (sustainedMph >= 45 || customersOut >= 50000)
      threat = "Level 3";
    else if (sustainedMph >= 30 || customersOut >= 15000)
      threat = "Level 2";
    else if (sustainedMph >= 20 || customersOut >= 5000) threat = "Level 1";

    return {
      "Predicted Incidents": incidents.round(),
      "Predicted Customers Out": customersOut.round(),
      "Suggested Crews": crews,
      "Threat Level": threat,
    };
  }
}
