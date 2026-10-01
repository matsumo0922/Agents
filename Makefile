.PHONY: link unlink status link-skills unlink-skills status-skills link-rules unlink-rules status-rules link-project unlink-project status-project

link: link-skills link-rules

unlink: unlink-skills unlink-rules

status: status-skills status-rules

link-skills:
	./scripts/link-skills.sh link

unlink-skills:
	./scripts/link-skills.sh unlink

status-skills:
	./scripts/link-skills.sh status

link-rules:
	./scripts/link-rules.sh link

unlink-rules:
	./scripts/link-rules.sh unlink

status-rules:
	./scripts/link-rules.sh status

link-project:
	./scripts/link-project-rules.sh link $(PROJECT)

unlink-project:
	./scripts/link-project-rules.sh unlink $(PROJECT)

status-project:
	./scripts/link-project-rules.sh status $(PROJECT)
