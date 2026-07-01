# Math formula corpus

A witness corpus for the opt-in TeX-math subset (#131). Formulas are drawn from
the KaTeX screenshotter data, the KaTeX support table, and the canonical math
examples those projects and Wikipedia publish. Supported constructs typeset
through the box-and-glue engine; unsupported constructs render as visible source
(a deliberate, witnessed fallback).

## Inline math in prose

The mass-energy relation $E = mc^2$ and the golden ratio $\varphi = \frac{1 + \sqrt{5}}{2}$
sit inline. A series $\sum_{i=0}^\infty \frac{1}{i^2}$ and a limit
$\lim_{x \to 0} \frac{\sin x}{x} = 1$ stay in the paragraph flow, as do relations
like $a \leq b$, $x \in S$, and $p \approx q$.

## Scripts and indices

$$x^2$$

$$x_i^2$$

$$a_{i,j}^{n+1}$$

$$e^{x^2}$$

$$2^{2^{x}}$$

$$\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$$

## Fractions and radicals

$$\frac{a}{b}$$

$$\frac{1}{1 + \frac{1}{1 + x}}$$

$$\sqrt{x}$$

$$\sqrt{x^2 + y^2}$$

$$\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$

$$\frac{\partial^2 f}{\partial x^2}$$

## Big operators with limits

$$\sum_{i=0}^\infty \frac{1}{i}$$

$$\prod_{k=1}^{n} k$$

$$\int_0^\infty e^{-x^2} = \frac{\sqrt{\pi}}{2}$$

$$\lim_{n \to \infty} \left(1 + \frac{1}{n}\right)^n = e$$

$$\bigcup_{i=1}^{n} A_i$$

## Greek letters

$$\alpha, \beta, \gamma, \delta, \epsilon, \theta, \lambda, \mu, \pi, \sigma, \phi, \omega$$

$$\Gamma, \Delta, \Theta, \Lambda, \Xi, \Pi, \Sigma, \Phi, \Psi, \Omega$$

$$\rho, \tau, \chi, \psi, \zeta, \eta, \kappa, \nu, \xi$$

## Relations and arrows

$$a \leq b, c \geq d, x \neq y, p \approx q, u \equiv v$$

$$x \in A, y \notin B, A \subset B, C \subseteq D, E \supseteq F$$

$$x \to y, a \leftarrow b, p \Rightarrow q, r \Leftrightarrow s, f \mapsto g$$

$$A \cup B, A \cap B, x \times y, a \cdot b, p \pm q, m \div n$$

## Functions

$$\sin^2 \theta + \cos^2 \theta = 1$$

$$\tan \theta = \frac{\sin \theta}{\cos \theta}$$

$$\log_b x = \frac{\ln x}{\ln b}$$

$$\operatorname{argmax}_x f(x)$$

## Famous formulas

$$e^{i\pi} + 1 = 0$$

$$a^2 + b^2 = c^2$$

$$f(x) = \sum_{n=0}^{\infty} \frac{x^n}{n!}$$

## Accents

$$\hat{x}$$

$$\bar{y}$$

$$\vec{v}$$

$$\overline{AB}$$

$$\tilde{z} + \dot{x}$$

## Matrices and cases

$$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$$

$$\begin{bmatrix} 1 & 0 \\ 0 & 1 \end{bmatrix}$$

$$\begin{cases} x & x \geq 0 \\ -x & x < 0 \end{cases}$$

## Advanced constructs rendered as visible source fallback

Color and other unsupported commands render as visible source rather than being
dropped.

$$\textcolor{red}{c}\boxed{x}$$
