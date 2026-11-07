import Foundation

/// O IMP Criativos é feito SOMENTE para criativos de **cassino online** e **apostas esportivas (bet)**
/// de operadores autorizados no Brasil. Não é um app de uso geral nem de rifas/sorteios.
///
/// Este arquivo é o ponto único que diz isso às IAs: todos os prompts (planejamento, interpretação,
/// limpeza, variações, análise, checagem e tentativa neutra) usam os textos abaixo.
/// Para mudar o tom ou as regras do nicho, mude aqui.
enum Niche {
    /// Nome curto, mostrado na interface.
    static let name = "Cassino e bet"

    /// Descrição em português, usada na interface.
    static let summary = "Criativos de cassino online e apostas esportivas (bet)"

    /// Contexto enviado às IAs, em inglês (os modelos seguem melhor).
    static let promptContext = """
    NICHE: this is an advertising creative for a licensed online casino or sports-betting ("bet") operator \
    in Brazil (regulated by Lei 14.790/2023). The tool only handles this niche.
    """

    /// O que conta como "assunto principal" num criativo do nicho.
    static let mainSubject = """
    The main subject is whatever the reference features: a casino game (its screen, reels, symbols, characters, \
    table, wheel or cards), a phone showing the game or the betting app, a person, an athlete, a ball or other \
    sports element, or the offer itself.
    """

    /// Avisos obrigatórios da publicidade de apostas no Brasil (Portaria SPA/MF 1.231/2024 e alterações).
    static let mandatoryNotices = """
    Keep any age notice ("18+", "proibido para menores de 18 anos") and any responsible-gambling message \
    (for example "Jogue com responsabilidade") that is in the image, legible, unless the user explicitly asked \
    to remove it. If such a notice contains a brand name, remove only the brand name.
    """

    /// Regras que nenhuma variação pode quebrar (coerência com o criativo de entrada).
    static let coherenceRules = """
    COHERENCE RULES (never break these):
    - Same game or same sport, same offer and same message as the reference. Keep the main subject recognizable, \
    with its real details; never swap it for another game, sport, team or character.
    - Do not add words, numbers, odds, multipliers, amounts, bonuses, prizes, cash, coins, people, logos, seals \
    or claims that are not in the reference.
    - Nothing may suggest guaranteed or easy winnings, income, investment or a solution to money problems.
    - No elements aimed at children (cartoon mascots, toys, school themes) unless they are already in the reference.
    """
}
