import Foundation

/// O IMP Criativos é feito SOMENTE para criativos de **cassino online** e **apostas esportivas (bet)**
/// de operadores autorizados no Brasil. Não é um app de uso geral nem de rifas/sorteios.
///
/// Cassino aqui é sempre ONLINE: jogos de celular/computador (slots, crash, mines, roleta e cartas ao vivo
/// transmitidas), com personagens e símbolos em 3D. Nada de cassino físico (prédio, salão, máquinas, Las Vegas).
///
/// Este arquivo é o ponto único que diz isso às IAs: todos os prompts (planejamento, interpretação,
/// limpeza, variações, análise, checagem e tentativa neutra) usam os textos abaixo.
/// Para mudar o tom ou as regras do nicho, mude aqui.
enum Niche {
    /// Nome curto, mostrado na interface.
    static let name = "Cassino online e bet"

    /// Descrição em português, usada na interface.
    static let summary = "Criativos de cassino online e apostas esportivas (bet)"

    /// Contexto enviado às IAs, em inglês (os modelos seguem melhor).
    static let promptContext = """
    NICHE: this is an advertising creative for a licensed ONLINE casino or sports-betting ("bet") operator \
    in Brazil (regulated by Lei 14.790/2023), played on a phone or computer. The tool only handles this niche. \
    The casino is always online: never turn the ad into a physical-casino scene (casino buildings or floors, rows \
    of slot machines, gaming tables in a venue, Las Vegas-style streets or signs).
    """

    /// O que conta como "assunto principal" num criativo do nicho.
    static let mainSubject = """
    The main subject is whatever the reference features: a 3D character or mascot of an online game, the game \
    itself (its screen, reels, symbols, gems, grid, wheel, cards or flying object), a phone showing the game or the \
    betting app, a person, an athlete, a ball or other sports element, or the offer itself.
    """

    /// Personagens 3D dos jogos online: fiéis ao original e com visual adulto.
    /// Desde 17/07/2026 (Portaria Interministerial MF/SECOM/MJSP nº 73/2026) a publicidade de apostas não pode usar
    /// imagens, personagens ou linguagem que atraiam menores; por isso o app nunca deixa o personagem mais infantil.
    static let characterRules = """
    3D CHARACTERS: if the reference has a 3D character or mascot, it is the same character in every variation: \
    identical species or design, proportions, colors, outfit, accessories and polished 3D render style, even when \
    the background style changes (pop art, pixel art, collage). Its pose, expression and camera angle may change \
    only to fit the direction. Never add a second character or a character from another game, never duplicate it, \
    never write text on it, and never make it cuter, younger or more childish: keep a premium, adult, cinematic look.
    """

    /// Avisos obrigatórios da publicidade de apostas no Brasil.
    /// Portaria SPA/MF 1.231/2024 (18+) e Portaria SPA/MF 1.964/2026 (advertência do Ministério da Fazenda,
    /// horizontal, legível, no mínimo 10% da área do anúncio, desde 17/07/2026).
    static let mandatoryNotices = """
    Keep every mandatory notice that is in the image, horizontal, clear and legible, never smaller than in the \
    reference: the "Ministério da Fazenda adverte: …" warning (it must keep at least 10% of the ad area), the age \
    notice ("18+" or "proibido para menores de 18 anos") and any responsible-gambling message (for example \
    "Jogue com responsabilidade"), unless the user explicitly asked to remove it. If such a notice contains a brand \
    name, remove only the brand name.
    """

    /// Regras que nenhuma variação pode quebrar (coerência com o criativo de entrada).
    static let coherenceRules = """
    COHERENCE RULES (never break these):
    - Same game or same sport, same offer and same message as the reference. Keep the main subject recognizable, \
    with its real details; never swap it for another game, sport, team or character.
    - Do not add words, numbers, odds, multipliers, amounts, bonuses, prizes, cash, coins, people, logos, seals \
    or claims that are not in the reference.
    - Nothing may suggest guaranteed or easy winnings, income, investment or a solution to money problems.
    - Nothing aimed at children: no new cartoon mascots, toys, school themes or childish styling.
    """
}
