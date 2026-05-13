(() => {
  const page = document.documentElement.dataset.page;
  if (!page) {
    return;
  }

  const STORAGE_KEY = "savoria-legal-language";
  const DEFAULT_LANGUAGE = "en";

  const pageCopy = {
    privacy: {
      en: {
        htmlLang: "en",
        title: "Savoria | Privacy Policy",
        description: "Savoria Privacy Policy.",
        navAriaLabel: "Primary navigation",
        navPrivacy: "Privacy Policy",
        navTerms: "Terms of Use",
        documentTitle: "Privacy Policy",
        documentLede: "This page explains what data Savoria processes, why it is used, who it may be shared with, and how you can exercise your rights.",
        documentMeta: "Last updated: May 13, 2026",
        languageLabel: "Language",
        languageHelper: "English is shown by default. Choose another language to view it.",
        relatedLabel: "Related document:",
        relatedLinkText: "Terms of Use"
      },
      "pt-BR": {
        htmlLang: "pt-BR",
        title: "Savoria | Política de Privacidade",
        description: "Política de Privacidade do Savoria.",
        navAriaLabel: "Navegação principal",
        navPrivacy: "Política de Privacidade",
        navTerms: "Termos de Uso",
        documentTitle: "Política de Privacidade",
        documentLede: "Esta página explica quais dados o Savoria processa, por que eles são usados, com quem podem ser compartilhados e como você pode exercer seus direitos.",
        documentMeta: "Última atualização: 13 de maio de 2026",
        languageLabel: "Idioma",
        languageHelper: "O inglês é exibido por padrão. Escolha outro idioma para visualizá-lo.",
        relatedLabel: "Documento relacionado:",
        relatedLinkText: "Termos de Uso"
      }
    },
    terms: {
      en: {
        htmlLang: "en",
        title: "Savoria | Terms of Use",
        description: "Savoria Terms of Use.",
        navAriaLabel: "Primary navigation",
        navPrivacy: "Privacy Policy",
        navTerms: "Terms of Use",
        documentTitle: "Terms of Use",
        documentLede: "These terms cover app usage, auto-renewable subscriptions, AI-powered features, user content, and the general rules that apply to Savoria.",
        documentMeta: "Last updated: May 13, 2026",
        languageLabel: "Language",
        languageHelper: "English is shown by default. Choose another language to view it.",
        relatedLabel: "Related document:",
        relatedLinkText: "Privacy Policy"
      },
      "pt-BR": {
        htmlLang: "pt-BR",
        title: "Savoria | Termos de Uso",
        description: "Termos de Uso do Savoria.",
        navAriaLabel: "Navegação principal",
        navPrivacy: "Política de Privacidade",
        navTerms: "Termos de Uso",
        documentTitle: "Termos de Uso",
        documentLede: "Estes termos cobrem o uso do app, assinaturas auto-renováveis, recursos com IA, conteúdo do usuário e as regras gerais aplicáveis ao Savoria.",
        documentMeta: "Última atualização: 13 de maio de 2026",
        languageLabel: "Idioma",
        languageHelper: "O inglês é exibido por padrão. Escolha outro idioma para visualizá-lo.",
        relatedLabel: "Documento relacionado:",
        relatedLinkText: "Política de Privacidade"
      }
    }
  };

  const pageTranslations = pageCopy[page];
  if (!pageTranslations) {
    return;
  }

  const availableLanguages = new Set(Object.keys(pageTranslations));
  const select = document.querySelector("[data-language-select]");
  const panels = Array.from(document.querySelectorAll("[data-language]"));
  const description = document.getElementById("page-description");
  const primaryNav = document.getElementById("primary-nav");
  const navPrivacy = document.getElementById("nav-link-privacy");
  const navTerms = document.getElementById("nav-link-terms");
  const documentTitle = document.getElementById("document-title");
  const documentLede = document.getElementById("document-lede");
  const documentMeta = document.getElementById("document-meta");
  const languageLabel = document.getElementById("language-label");
  const languageHelper = document.getElementById("language-helper");
  const relatedLabel = document.getElementById("related-label");
  const relatedLink = document.getElementById("related-link");

  const applyLanguage = (requestedLanguage) => {
    const nextLanguage = availableLanguages.has(requestedLanguage)
      ? requestedLanguage
      : DEFAULT_LANGUAGE;
    const copy = pageTranslations[nextLanguage];

    document.documentElement.lang = copy.htmlLang;
    document.title = copy.title;

    if (description) {
      description.setAttribute("content", copy.description);
    }

    if (primaryNav) {
      primaryNav.setAttribute("aria-label", copy.navAriaLabel);
    }

    if (navPrivacy) {
      navPrivacy.textContent = copy.navPrivacy;
    }

    if (navTerms) {
      navTerms.textContent = copy.navTerms;
    }

    if (documentTitle) {
      documentTitle.textContent = copy.documentTitle;
    }

    if (documentLede) {
      documentLede.textContent = copy.documentLede;
    }

    if (documentMeta) {
      documentMeta.textContent = copy.documentMeta;
    }

    if (languageLabel) {
      languageLabel.textContent = copy.languageLabel;
    }

    if (languageHelper) {
      languageHelper.textContent = copy.languageHelper;
    }

    if (relatedLabel) {
      relatedLabel.textContent = copy.relatedLabel;
    }

    if (relatedLink) {
      relatedLink.textContent = copy.relatedLinkText;
    }

    panels.forEach((panel) => {
      const isVisible = panel.getAttribute("data-language") === nextLanguage;
      panel.hidden = !isVisible;
      panel.setAttribute("aria-hidden", String(!isVisible));
    });

    if (select && select.value !== nextLanguage) {
      select.value = nextLanguage;
    }

    window.localStorage.setItem(STORAGE_KEY, nextLanguage);
  };

  if (select) {
    select.addEventListener("change", (event) => {
      applyLanguage(event.target.value);
    });
  }

  const savedLanguage = window.localStorage.getItem(STORAGE_KEY);
  applyLanguage(savedLanguage || DEFAULT_LANGUAGE);
})();