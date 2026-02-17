import UIKit

final class MatchTableViewCell: UITableViewCell {

    static let reuseIdentifier = "MatchTableViewCell"

    private let teamANameLabel = UILabel()
    private let teamBNameLabel = UILabel()
    private let teamAOddsLabel = UILabel()
    private let teamBOddsLabel = UILabel()
    private let startTimeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var previousOdds: MatchOdds?

    override func prepareForReuse() {
        super.prepareForReuse()
        previousOdds = nil
        teamAOddsLabel.layer.removeAllAnimations()
        teamBOddsLabel.layer.removeAllAnimations()
        teamAOddsLabel.textColor = .secondaryLabel
        teamBOddsLabel.textColor = .secondaryLabel
        teamAOddsLabel.transform = .identity
        teamBOddsLabel.transform = .identity
    }

    func configure(with data: MatchWithOdds) {
        let shouldBlink = previousOdds != nil
            && (previousOdds?.teamAOdds != data.odds.teamAOdds
                || previousOdds?.teamBOdds != data.odds.teamBOdds)

        teamANameLabel.text = data.match.teamA
        teamBNameLabel.text = data.match.teamB
        teamAOddsLabel.text = String(format: "%.2f", data.odds.teamAOdds)
        teamBOddsLabel.text = String(format: "%.2f", data.odds.teamBOdds)
        startTimeLabel.text = DateFormatterProvider.matchTime.string(from: data.match.startTime)

        if shouldBlink {
            blinkOddsLabels()
        }

        previousOdds = data.odds
    }

    private func blinkOddsLabels() {
        let blinkTextColor = UIColor.black

        let originalAColor = teamAOddsLabel.textColor
        let originalBColor = teamBOddsLabel.textColor

        // Flash on
        UIView.animate(withDuration: 0.15) {
            self.teamAOddsLabel.textColor = blinkTextColor
            self.teamBOddsLabel.textColor = blinkTextColor
            self.teamAOddsLabel.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            self.teamBOddsLabel.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        } completion: { _ in
            // Hold briefly, then fade out
            UIView.animate(withDuration: 0.6, delay: 0.4, options: .curveEaseOut) {
                self.teamAOddsLabel.textColor = originalAColor
                self.teamBOddsLabel.textColor = originalBColor
                self.teamAOddsLabel.transform = .identity
                self.teamBOddsLabel.transform = .identity
            }
        }
    }

    // MARK: - Layout

    private func setupViews() {
        selectionStyle = .none

        teamANameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        teamBNameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        teamBNameLabel.textAlignment = .right

        teamAOddsLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        teamAOddsLabel.textColor = .secondaryLabel
        teamBOddsLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        teamBOddsLabel.textColor = .secondaryLabel
        teamBOddsLabel.textAlignment = .right

        startTimeLabel.font = .systemFont(ofSize: 12)
        startTimeLabel.textColor = .tertiaryLabel
        startTimeLabel.textAlignment = .center

        let namesRow = UIStackView(arrangedSubviews: [teamANameLabel, teamBNameLabel])
        namesRow.axis = .horizontal
        namesRow.distribution = .fillEqually

        let oddsRow = UIStackView(arrangedSubviews: [teamAOddsLabel, teamBOddsLabel])
        oddsRow.axis = .horizontal
        oddsRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [namesRow, oddsRow, startTimeLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 48),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -48),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
}
