.PHONY: link unlink status link-skills unlink-skills status-skills link-rules unlink-rules status-rules link-agents unlink-agents status-agents link-project unlink-project status-project

link: link-skills link-rules link-agents

unlink: unlink-skills unlink-rules unlink-agents

status: status-skills status-rules status-agents

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

link-agents:
	./scripts/link-agents.sh link

unlink-agents:
	./scripts/link-agents.sh unlink

status-agents:
	./scripts/link-agents.sh status

link-project:
	./scripts/link-project-rules.sh link $(PROJECT)

unlink-project:
	./scripts/link-project-rules.sh unlink $(PROJECT)

status-project:
	./scripts/link-project-rules.sh status $(PROJECT)
