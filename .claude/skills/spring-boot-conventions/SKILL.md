---
name: spring-boot-conventions
description: Spring Boot 4.x conventions for this project — dependency and config patterns. Use when adding dependencies, wiring config, or touching pom.xml.
---

# Spring Boot Conventions for RosterForge

- Spring Boot 4.x uses `spring-boot-starter-webmvc` (not `-web`, deprecated) and
  per-feature test starters (`spring-boot-starter-*-test`), not one monolithic
  `spring-boot-starter-test`. Don't "fix" these back to Boot 3-era names.
- All config values with real or even placeholder-sensitive meaning go through
  Spring Cloud Vault or `${VAR:default}` placeholders — never hardcoded secrets,
  even throwaway local ones, once Vault is wired.
- New Testcontainers modules: add to the `org.testcontainers` groupId, no version
  needed on the individual dependency — version comes from the `testcontainers-bom`
  import in dependencyManagement. Don't add per-dependency versions for these.
- Prefer explicit `<dependencyManagement>` overrides over silently living with a
  known CVE in a transitive dependency.