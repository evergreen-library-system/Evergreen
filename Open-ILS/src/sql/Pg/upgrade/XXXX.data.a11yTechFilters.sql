BEGIN;

INSERT INTO config.record_attr_definition (name,label,sorter,filter,tag,sf_list,multi,vocabulary) VALUES
 ('a11yAccessMode',oils_i18n_gettext('a11yAccessMode', 'Content access mode', 'crad', 'label'),FALSE,TRUE,'341','a',TRUE,'https://schema.org/accessMode'),
 ('a11yTextFeatures',oils_i18n_gettext('a11yTextFeatures', 'Textual assistive features', 'crad', 'label'),FALSE,TRUE,'341','b',TRUE,'https://schema.org/accessibilityFeature'),
 ('a11yVisualFeatures',oils_i18n_gettext('a11yVisualFeatures', 'Visual assistive features', 'crad', 'label'),FALSE,TRUE,'341','c',TRUE,'https://schema.org/accessibilityFeature'),
 ('a11yAuditoryFeatures',oils_i18n_gettext('a11yAuditoryFeatures', 'Auditory assistive features', 'crad', 'label'),FALSE,TRUE,'341','d',TRUE,'https://schema.org/accessibilityFeature'),
 ('a11yTactileFeatures',oils_i18n_gettext('a11yTactileFeatures', 'Tactile assistive features', 'crad', 'label'),FALSE,TRUE,'341','e',TRUE,'https://schema.org/accessibilityFeature')
;

-- XXX COMMITER!!! Make sure 1753 is the next id stock id to be supplied in 950.data.seed-values.sql!

INSERT INTO config.coded_value_map (id, opac_visible, ctype, code, value, search_label) VALUES
 (1753,true,'a11yAccessMode','auditory',oils_i18n_gettext('1753','Auditory','ccvm','value'),oils_i18n_gettext('1753','Auditory','ccvm','search_label')),
 (1754,true,'a11yAccessMode','textual',oils_i18n_gettext('1754','Textual','ccvm','value'),oils_i18n_gettext('1754','Textual','ccvm','search_label')),
 (1755,true,'a11yAccessMode','visual',oils_i18n_gettext('1755','Visual','ccvm','value'),oils_i18n_gettext('1755','Visual','ccvm','search_label')),
 (1756,true,'a11yAccessMode','tactile',oils_i18n_gettext('1756','Tactile','ccvm','value'),oils_i18n_gettext('1756','Tactile','ccvm','search_label')),
 (1757,true,'a11yTextFeatures','annotations',oils_i18n_gettext('1757','annotations','ccvm','value'),oils_i18n_gettext('1757','Annotations','ccvm','search_label')),
 (1758,true,'a11yTextFeatures','ARIA',oils_i18n_gettext('1758','ARIA','ccvm','value'),oils_i18n_gettext('1758','ARIA','ccvm','search_label')),
 (1759,true,'a11yTextFeatures','bookmarks',oils_i18n_gettext('1759','bookmarks','ccvm','value'),oils_i18n_gettext('1759','Bookmarks','ccvm','search_label')),
 (1760,true,'a11yTextFeatures','index',oils_i18n_gettext('1760','index','ccvm','value'),oils_i18n_gettext('1760','Index','ccvm','search_label')),
 (1761,true,'a11yTextFeatures','pageBreakMarkers',oils_i18n_gettext('1761','pageBreakMarkers','ccvm','value'),oils_i18n_gettext('1761','Page break markers','ccvm','search_label')),
 (1762,false,'a11yTextFeatures','pageNavigation',oils_i18n_gettext('1762','pageNavigation','ccvm','value'),oils_i18n_gettext('1762','Page navigation','ccvm','search_label')),
 (1763,true,'a11yTextFeatures','readingOrder',oils_i18n_gettext('1763','readingOrder','ccvm','value'),oils_i18n_gettext('1763','Reading order','ccvm','search_label')),
 (1764,true,'a11yTextFeatures','structuralNavigation',oils_i18n_gettext('1764','structuralNavigation','ccvm','value'),oils_i18n_gettext('1764','Structural navigation','ccvm','search_label')),
 (1765,true,'a11yTextFeatures','tableOfContents',oils_i18n_gettext('1765','tableOfContents','ccvm','value'),oils_i18n_gettext('1765','Table of contents','ccvm','search_label')),
 (1766,true,'a11yTextFeatures','taggedPDF',oils_i18n_gettext('1766','taggedPDF','ccvm','value'),oils_i18n_gettext('1766','Tagged PDF','ccvm','search_label')),
 (1767,true,'a11yTextFeatures','alternativeText',oils_i18n_gettext('1767','alternativeText','ccvm','value'),oils_i18n_gettext('1767','Alternative text','ccvm','search_label')),
 (1768,true,'a11yTextFeatures','captions',oils_i18n_gettext('1768','captions','ccvm','value'),oils_i18n_gettext('1768','Captions','ccvm','search_label')),
 (1769,true,'a11yTextFeatures','closedCaptions',oils_i18n_gettext('1769','closedCaptions','ccvm','value'),oils_i18n_gettext('1769','Closed captions','ccvm','search_label')),
 (1770,true,'a11yTextFeatures','describedMath',oils_i18n_gettext('1770','describedMath','ccvm','value'),oils_i18n_gettext('1770','Described math','ccvm','search_label')),
 (1771,true,'a11yTextFeatures','longDescription',oils_i18n_gettext('1771','longDescription','ccvm','value'),oils_i18n_gettext('1771','Long description','ccvm','search_label')),
 (1772,true,'a11yTextFeatures','openCaptions',oils_i18n_gettext('1772','openCaptions','ccvm','value'),oils_i18n_gettext('1772','Open captions','ccvm','search_label')),
 (1773,true,'a11yTextFeatures','transcript',oils_i18n_gettext('1773','transcript','ccvm','value'),oils_i18n_gettext('1773','transcript','ccvm','search_label')),
 (1774,true,'a11yTextFeatures','displayTransformability',oils_i18n_gettext('1774','displayTransformability','ccvm','value'),oils_i18n_gettext('1774','Display transformability','ccvm','search_label')),
 (1775,true,'a11yTextFeatures','ChemML',oils_i18n_gettext('1775','ChemML','ccvm','value'),oils_i18n_gettext('1775','ChemML','ccvm','search_label')),
 (1776,true,'a11yTextFeatures','latex',oils_i18n_gettext('1776','latex','ccvm','value'),oils_i18n_gettext('1776','LaTeX','ccvm','search_label')),
 (1777,false,'a11yTextFeatures','latex-chemistry',oils_i18n_gettext('1777','latex-chemistry','ccvm','value'),oils_i18n_gettext('1777','LaTeX-chemistry','ccvm','search_label')),
 (1778,true,'a11yTextFeatures','MathML',oils_i18n_gettext('1778','MathML','ccvm','value'),oils_i18n_gettext('1778','MathML','ccvm','search_label')),
 (1779,false,'a11yTextFeatures','MathML-chemistry',oils_i18n_gettext('1779','MathML-chemistry','ccvm','value'),oils_i18n_gettext('1779','MathML-chemistry','ccvm','search_label')),
 (1780,true,'a11yTextFeatures','ttsMarkup',oils_i18n_gettext('1780','ttsMarkup','ccvm','value'),oils_i18n_gettext('1780','TTS markup','ccvm','search_label')),
 (1781,true,'a11yTextFeatures','largePrint',oils_i18n_gettext('1781','largePrint','ccvm','value'),oils_i18n_gettext('1781','Large print','ccvm','search_label')),
 (1782,false,'a11yTextFeatures','horizontalWriting',oils_i18n_gettext('1782','horizontalWriting','ccvm','value'),oils_i18n_gettext('1782','Horizontal writing','ccvm','search_label')),
 (1783,false,'a11yTextFeatures','verticalWriting',oils_i18n_gettext('1783','verticalWriting','ccvm','value'),oils_i18n_gettext('1783','VerticalWriting','ccvm','search_label')),
 (1784,false,'a11yTextFeatures','withAdditionalWordSegmentation',oils_i18n_gettext('1784','withAdditionalWordSegmentation','ccvm','value'),oils_i18n_gettext('1784','With additional word segmentation','ccvm','search_label')),
 (1785,false,'a11yTextFeatures','withoutAdditionalWordSegmentation',oils_i18n_gettext('1785','withoutAdditionalWordSegmentation','ccvm','value'),oils_i18n_gettext('1785','Without additional word segmentation','ccvm','search_label')),
 (1786,true,'a11yVisualFeatures','highContrastDisplay',oils_i18n_gettext('1786','highContrastDisplay','ccvm','value'),oils_i18n_gettext('1786','High contrast display','ccvm','search_label')),
 (1787,true,'a11yVisualFeatures','signLanguage',oils_i18n_gettext('1787','signLanguage','ccvm','value'),oils_i18n_gettext('1787','Sign language','ccvm','search_label')),
 (1788,true,'a11yAuditoryFeatures','audioDescription',oils_i18n_gettext('1788','audioDescription','ccvm','value'),oils_i18n_gettext('1788','Audio description','ccvm','search_label')),
 (1789,true,'a11yAuditoryFeatures','highContrastAudio',oils_i18n_gettext('1789','highContrastAudio','ccvm','value'),oils_i18n_gettext('1789','High contrast audio','ccvm','search_label')),
 (1790,true,'a11yAuditoryFeatures','timingControl',oils_i18n_gettext('1790','timingControl','ccvm','value'),oils_i18n_gettext('1790','Timing control','ccvm','search_label')),
 (1791,true,'a11yAuditoryFeatures','synchronizedAudioText',oils_i18n_gettext('1791','synchronizedAudioText','ccvm','value'),oils_i18n_gettext('1791','Synchronized audio text','ccvm','search_label')),
 (1792,true,'a11yTactileFeatures','braille',oils_i18n_gettext('1792','braille','ccvm','value'),oils_i18n_gettext('1792','Braille','ccvm','search_label')),
 (1793,false,'a11yTactileFeatures','tactileGraphic',oils_i18n_gettext('1793','tactileGraphic','ccvm','value'),oils_i18n_gettext('1793','Tactile graphic','ccvm','search_label')),
 (1794,false,'a11yTactileFeatures','tactileObject',oils_i18n_gettext('1794','tactileObject','ccvm','value'),oils_i18n_gettext('1794','Tactile object','ccvm','search_label'))
;

-- The above is autogenerated from LoC data; because we use metabib.full_rec to look up the
-- in-record value, we have to make our CCVM value lowercase, as that's how MFR stores the data.
UPDATE config.coded_value_map SET code = LOWER(code) WHERE code <> LOWER(code) AND ctype LIKE 'a11y%';

COMMIT;

