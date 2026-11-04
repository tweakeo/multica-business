"use client";

import { useWorkspacePaths } from "@multica/core/paths";
import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@multica/ui/components/ui/sidebar";
import { AppLink } from "../navigation";
import { useT } from "../i18n";
import { AREAS } from "../empresa/shared";
import { routeIconForPath } from "./route-icon-components";

const NAV_ITEM_CLASS_NAME =
  "text-muted-foreground hover:not-data-active:bg-sidebar-accent/70 data-active:bg-sidebar-accent data-active:text-sidebar-accent-foreground";

/**
 * TLS "Empresa" group: company overview plus the six business areas in
 * presentation order. Area names are business data, shown as-is. Areas are
 * text-only sub-items indented under "Empresa": the name is the signal, so no
 * per-area dot or icon competes with it.
 */
export function EmpresaNavGroup({ pathname }: { pathname: string }) {
  const { t } = useT("layout");
  const p = useWorkspacePaths();
  const overview = p.empresa();
  const Icon = routeIconForPath(overview);
  return (
    <SidebarGroup>
      <SidebarGroupLabel>{t(($) => $.sidebar.empresa_group)}</SidebarGroupLabel>
      <SidebarGroupContent>
        <SidebarMenu className="gap-0.5">
          <SidebarMenuItem>
            <SidebarMenuButton isActive={pathname === overview} render={<AppLink href={overview} />} className={NAV_ITEM_CLASS_NAME}>
              <Icon />
              <span>{t(($) => $.nav.empresa)}</span>
            </SidebarMenuButton>
          </SidebarMenuItem>
          {AREAS.map((area) => {
            const href = p.empresaArea(area.code);
            return (
              <SidebarMenuItem key={area.code}>
                <SidebarMenuButton
                  isActive={pathname === href || pathname.startsWith(`${href}/`)}
                  render={<AppLink href={href} />}
                  className={`${NAV_ITEM_CLASS_NAME} pl-8`}
                >
                  <span>{area.name}</span>
                </SidebarMenuButton>
              </SidebarMenuItem>
            );
          })}
        </SidebarMenu>
      </SidebarGroupContent>
    </SidebarGroup>
  );
}
