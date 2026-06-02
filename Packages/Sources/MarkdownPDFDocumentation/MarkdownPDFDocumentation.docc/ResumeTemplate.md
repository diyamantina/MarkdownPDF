# Resume Template

The generic renderer stays in `MarkdownPDF`. The resume and CV layer lives in
`MarkdownPDFResume` and only produces Markdown from structured data. The
`resumepdf` executable is the composition root that combines that template with
the generic Markdown renderer.

## Research Inputs

The template is intentionally conservative. Journal evidence points toward clear
section structure, direct evidence in experience and education, and avoiding
decorative cues that invite irrelevant inference.

- Pina et al., "Using Machine Learning with Eye-Tracking Data to Predict if a
  Recruiter Will Approve a Resume", Machine Learning and Knowledge Extraction,
  2023. The study reports that recruiter eye-tracking features and time spent on
  experience and education were predictive of screening outcomes, and recommends
  clear, concise descriptions in those sections.
  https://doi.org/10.3390/make5030038
- Furtmueller, Wilderom, and Tate, "Managing recruitment and selection in the
  digital age: e-HRM and resumes", Human Systems Management, 2011. The paper
  identifies digital resume database and matching challenges, which argues for
  structured, predictable fields.
  https://doi.org/10.3233/HSM-2011-0753
- Risavy, Robie, Fisher, and Rasheed, "Resumes vs. application forms: Why the
  stubborn reliance on resumes?", Frontiers in Psychology, 2022. The article
  argues that structured application forms have validity advantages over freeform
  resumes, which supports a typed input model for this template.
  https://doi.org/10.3389/fpsyg.2022.884205
- Cole, Rubin, Feild, and Giles, "Recruiters' perceptions and use of applicant
  resume information: Screening the recent graduate", Applied Psychology, 2007.
  The paper is a peer-reviewed source on how recruiters use resume information.
  https://doi.org/10.1111/j.1464-0597.2007.00288.x
- Apers and Derous, "Are they accurate? Recruiters' personality judgments in
  paper versus video resumes", Computers in Human Behavior, 2017. The findings
  argue against richer media as a fix for screening accuracy, so this template
  keeps job-relevant text prominent.
  https://doi.org/10.1016/j.chb.2017.02.063

## Template Rules

- One column.
- Name, headline, and contact links first.
- Experience before education for working professionals.
- Experience entries use company, dates, and title in one heading.
- Project or product names are nested under a job when useful.
- Highlights remain semantic Markdown list items. The generic renderer decides
  how lists appear in the PDF.
- Technologies are plain text fields, not decorative tags.
- Skills are grouped, compact, and near the end.
- The template does not add photos, icons, sidebars, or visual scoring elements.

## Use

```sh
cd Packages
swift run resumepdf Tests/MarkdownPDFResumeTests/Fixtures/democv.json .build/democv-template.pdf
```
